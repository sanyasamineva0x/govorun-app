#!/usr/bin/env python3

import argparse
import hashlib
import json
import math
import os
import statistics
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
HELPER_SOURCE = REPO_ROOT / "scripts" / "benchmark-full-pipeline-helper.swift"
HELPER_BINARY = REPO_ROOT / "build" / "benchmark-full-pipeline-helper"
HELPER_SWIFT_SOURCES = [
    REPO_ROOT / "Govorun/Models/LLMOutputContract.swift",
    REPO_ROOT / "Govorun/Models/SnippetContext.swift",
    REPO_ROOT / "Govorun/Models/SnippetPlaceholder.swift",
    REPO_ROOT / "Govorun/Models/SuperTextStyle.swift",
    REPO_ROOT / "Govorun/Core/NumberNormalizer.swift",
    REPO_ROOT / "Govorun/Core/NormalizationGate.swift",
    REPO_ROOT / "Govorun/Core/NormalizationPipeline.swift",
    HELPER_SOURCE,
]


class BenchmarkError(Exception):
    pass


class BenchmarkConfigurationError(BenchmarkError):
    pass


class FullPipelineHelperError(BenchmarkError):
    pass


class FullPipelineHelperUnavailableError(FullPipelineHelperError):
    pass


class LLMRequestError(BenchmarkError):
    pass


LEGACY_TEXT_MODE_TO_SUPER_STYLE = {
    "chat": "relaxed",
    "note": "relaxed",
    "email": "formal",
    "document": "normal",
    "code": "normal",
    "universal": "normal",
}


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Benchmark local LLM normalization via OpenAI-compatible endpoint."
    )
    parser.add_argument(
        "--dataset",
        default="benchmarks/llm-normalization-seed.jsonl",
        help="Path to JSONL dataset.",
    )
    parser.add_argument(
        "--base-url",
        default="http://127.0.0.1:8080/v1",
        help="Base URL for local OpenAI-compatible server.",
    )
    parser.add_argument(
        "--model",
        default="local-model",
        help="Model identifier passed to the endpoint.",
    )
    parser.add_argument(
        "--system-prompt-file",
        help="Optional text file with system prompt. If omitted, only user text is sent.",
    )
    parser.add_argument(
        "--output",
        default="build/llm-normalization-benchmark-results.jsonl",
        help="Where to store per-sample raw results.",
    )
    parser.add_argument(
        "--summary",
        default="build/llm-normalization-benchmark-summary.json",
        help="Where to store aggregated metrics.",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=300.0,
        help="HTTP timeout in seconds.",
    )
    parser.add_argument(
        "--max-tokens",
        type=int,
        default=128,
        help="Max tokens for completion.",
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=0.0,
        help="Sampling temperature.",
    )
    parser.add_argument(
        "--stop",
        nargs="*",
        default=None,
        help="Stop sequences (e.g. --stop '\\n\\n').",
    )
    parser.add_argument(
        "--warmup",
        type=int,
        default=1,
        help="How many initial samples to run as warmup without recording summary metrics.",
    )
    parser.add_argument(
        "--server-pid",
        type=int,
        help="Optional PID of local LLM server to sample RSS via ps.",
    )
    parser.add_argument(
        "--pipeline-mode",
        choices=["llm-only", "full-pipeline"],
        default="llm-only",
        help="Benchmark only the LLM input/output contract or the full normalization pipeline.",
    )
    parser.add_argument(
        "--super-style",
        default="normal",
        choices=["relaxed", "normal", "formal"],
        help="SuperTextStyle raw value for generated production prompt in full-pipeline mode.",
    )
    parser.add_argument(
        "--text-mode",
        help="Deprecated legacy alias. Maps chat/note→relaxed, email→formal, document/code/universal→normal.",
    )
    parser.add_argument(
        "--current-date",
        help="Optional date in YYYY-MM-DD for generated production prompt in full-pipeline mode.",
    )
    parser.add_argument(
        "--expected-key",
        help="Optional dataset field to compare against. By default full-pipeline prefers expected_full_pipeline, then expected.",
    )
    parser.add_argument(
        "--no-terminal-period",
        action="store_true",
        help="Disable terminal period policy in full-pipeline mode.",
    )
    return parser.parse_args()


def resolve_super_style(args: argparse.Namespace) -> str:
    if args.text_mode:
        style = LEGACY_TEXT_MODE_TO_SUPER_STYLE.get(args.text_mode)
        if style is None:
            raise BenchmarkConfigurationError(
                f"Unsupported legacy --text-mode value: {args.text_mode}"
            )
        print(
            f"WARNING: --text-mode is deprecated, use --super-style {style} instead.",
            file=sys.stderr,
        )
        return style
    return args.super_style


def load_dataset(path: Path) -> list[dict]:
    if not path.exists():
        raise BenchmarkConfigurationError(f"Dataset file not found: {path}")
    if not path.is_file():
        raise BenchmarkConfigurationError(f"Dataset path is not a file: {path}")

    rows: list[dict] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            line = raw_line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                raise BenchmarkConfigurationError(
                    f"Invalid JSON in dataset {path}:{line_number}: {exc.msg}"
                ) from exc
            if not isinstance(row, dict):
                raise BenchmarkConfigurationError(
                    f"Dataset row {path}:{line_number} must be a JSON object"
                )
            if not isinstance(row.get("input"), str):
                raise BenchmarkConfigurationError(
                    f"Dataset row {path}:{line_number} must contain string field 'input'"
                )
            rows.append(row)

    if not rows:
        raise BenchmarkConfigurationError(f"Dataset is empty: {path}")
    return rows


def load_system_prompt(path: str | None) -> str | None:
    if not path:
        return None
    prompt_path = Path(path)
    if not prompt_path.exists():
        raise BenchmarkConfigurationError(f"System prompt file not found: {prompt_path}")
    if not prompt_path.is_file():
        raise BenchmarkConfigurationError(f"System prompt path is not a file: {prompt_path}")
    return prompt_path.read_text(encoding="utf-8").strip()


def prompt_sha256(prompt: str | None) -> str | None:
    if prompt is None:
        return None
    return hashlib.sha256(prompt.encode("utf-8")).hexdigest()


def validate_expected_key(dataset: list[dict], expected_key: str | None) -> None:
    if expected_key is None:
        return
    if not expected_key.strip():
        raise BenchmarkConfigurationError("--expected-key must not be empty")

    missing_ids = [
        str(sample.get("id", "?"))
        for sample in dataset
        if expected_key not in sample
    ]
    if not missing_ids:
        return

    preview = ", ".join(missing_ids[:5])
    suffix = "" if len(missing_ids) <= 5 else f" and {len(missing_ids) - 5} more"
    raise BenchmarkConfigurationError(
        f"Dataset field '{expected_key}' is missing in {len(missing_ids)} sample(s): {preview}{suffix}"
    )


def ensure_full_pipeline_helper(binary_path: Path) -> Path:
    missing_sources = [str(source) for source in HELPER_SWIFT_SOURCES if not source.exists()]
    if missing_sources:
        raise BenchmarkConfigurationError(
            "Missing helper source files: " + ", ".join(missing_sources)
        )

    binary_path.parent.mkdir(parents=True, exist_ok=True)
    if binary_path.exists():
        binary_mtime = binary_path.stat().st_mtime
        if all(source.exists() and source.stat().st_mtime <= binary_mtime for source in HELPER_SWIFT_SOURCES):
            return binary_path

    compile_cmd = [
        "xcrun",
        "swiftc",
        "-enable-bare-slash-regex",
        *[str(source) for source in HELPER_SWIFT_SOURCES],
        "-o",
        str(binary_path),
    ]
    try:
        subprocess.run(
            compile_cmd,
            check=True,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip()
        stdout = (exc.stdout or "").strip()
        details = stderr or stdout or "swiftc failed without stderr output"
        raise BenchmarkConfigurationError(
            f"Failed to compile full-pipeline helper: {details}"
        ) from exc
    return binary_path


class FullPipelineHelper:
    def __init__(self, binary_path: Path) -> None:
        try:
            self.process = subprocess.Popen(
                [str(binary_path)],
                cwd=REPO_ROOT,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                bufsize=1,
            )
        except OSError as exc:
            raise FullPipelineHelperUnavailableError(
                f"Failed to start full-pipeline helper: {exc}"
            ) from exc

    def _stderr_snapshot(self) -> str:
        if self.process.stderr is None:
            return ""
        if self.process.poll() is None:
            return ""
        return self.process.stderr.read().strip()

    def request(self, payload: dict) -> dict:
        if self.process.stdin is None or self.process.stdout is None:
            raise FullPipelineHelperUnavailableError("Full pipeline helper pipes are not available")
        if self.process.poll() is not None:
            stderr = self._stderr_snapshot()
            raise FullPipelineHelperUnavailableError(
                f"Full pipeline helper is not running: {stderr or 'no stderr output'}"
            )

        try:
            self.process.stdin.write(json.dumps(payload, ensure_ascii=False) + "\n")
            self.process.stdin.flush()
        except (BrokenPipeError, OSError) as exc:
            stderr = self._stderr_snapshot()
            raise FullPipelineHelperUnavailableError(
                f"Failed to send request to full-pipeline helper: {stderr or exc}"
            ) from exc

        line = self.process.stdout.readline()
        if not line:
            stderr = self._stderr_snapshot()
            raise FullPipelineHelperUnavailableError(
                f"Full pipeline helper exited unexpectedly: {stderr or 'no stderr output'}"
            )

        try:
            response = json.loads(line)
        except json.JSONDecodeError as exc:
            raise FullPipelineHelperError(
                f"Full pipeline helper returned invalid JSON: {line.strip()}"
            ) from exc
        if not response.get("ok"):
            raise FullPipelineHelperError(response.get("error", "unknown helper error"))
        return response

    def close(self) -> None:
        if self.process.poll() is not None:
            return
        self.process.terminate()
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.kill()


def resolve_expected(sample: dict, args: argparse.Namespace) -> tuple[str, str | None]:
    if args.expected_key:
        return args.expected_key, sample.get(args.expected_key)

    if args.pipeline_mode == "full-pipeline" and "expected_full_pipeline" in sample:
        return "expected_full_pipeline", sample.get("expected_full_pipeline")

    return "expected", sample.get("expected")


def resolve_system_prompt(
    *,
    args: argparse.Namespace,
    helper: FullPipelineHelper | None,
    effective_super_style: str,
) -> tuple[str | None, str | None]:
    if args.system_prompt_file:
        return load_system_prompt(args.system_prompt_file), args.system_prompt_file

    if args.pipeline_mode != "full-pipeline":
        return None, None

    if helper is None:
        raise BenchmarkConfigurationError(
            "Full pipeline helper is required to generate the production system prompt"
        )

    response = helper.request({
        "op": "prompt",
        "superStyle": effective_super_style,
        "currentDate": args.current_date,
    })
    return response["systemPrompt"], "<generated-from-production>"


def require_full_pipeline_helper(helper: FullPipelineHelper | None) -> FullPipelineHelper:
    if helper is None:
        raise BenchmarkConfigurationError("Full pipeline helper is not initialized")
    return helper


def request_completion(
    *,
    base_url: str,
    model: str,
    user_text: str,
    system_prompt: str | None,
    timeout: float,
    max_tokens: int,
    temperature: float,
    stop: list[str] | None = None,
) -> tuple[str, float | None, float]:
    payload = {
        "model": model,
        "stream": True,
        "temperature": temperature,
        "max_tokens": max_tokens,
        "messages": [],
    }
    if stop:
        payload["stop"] = stop

    if system_prompt:
        payload["messages"].append({"role": "system", "content": system_prompt})
    payload["messages"].append({"role": "user", "content": user_text})

    request = urllib.request.Request(
        url=f"{base_url.rstrip('/')}/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
        },
        method="POST",
    )

    start = time.perf_counter()
    first_token_latency_ms: float | None = None
    output_parts: list[str] = []

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            while True:
                raw_line = response.readline()
                if not raw_line:
                    break

                line = raw_line.decode("utf-8", errors="ignore").strip()
                if not line or not line.startswith("data: "):
                    continue

                data = line[6:]
                if data == "[DONE]":
                    break

                try:
                    chunk = json.loads(data)
                except json.JSONDecodeError as exc:
                    raise LLMRequestError(f"Malformed SSE chunk: {data}") from exc
                choices = chunk.get("choices") or []
                if not choices:
                    continue

                delta = choices[0].get("delta") or {}
                content = delta.get("content")
                if not content:
                    continue

                if first_token_latency_ms is None:
                    first_token_latency_ms = (time.perf_counter() - start) * 1000.0

                output_parts.append(content)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="ignore")
        raise LLMRequestError(f"HTTP {exc.code}: {body}") from exc
    except urllib.error.URLError as exc:
        raise LLMRequestError(f"Connection error: {exc}") from exc
    except OSError as exc:
        raise LLMRequestError(f"Socket error during streaming: {exc}") from exc

    total_latency_ms = (time.perf_counter() - start) * 1000.0
    return "".join(output_parts).strip(), first_token_latency_ms, total_latency_ms


def read_rss_kb(pid: int | None) -> int | None:
    if pid is None:
        return None

    try:
        completed = subprocess.run(
            ["ps", "-o", "rss=", "-p", str(pid)],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.SubprocessError:
        return None

    raw = completed.stdout.strip()
    if not raw:
        return None

    try:
        return int(raw)
    except ValueError:
        return None


def percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]

    index = (len(ordered) - 1) * q
    lower = math.floor(index)
    upper = math.ceil(index)
    if lower == upper:
        return ordered[int(index)]

    weight = index - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def summarize(rows: list[dict]) -> dict:
    def collect(metric: str, bucket: str | None = None) -> list[float]:
        values: list[float] = []
        for row in rows:
            if bucket is not None and row.get("bucket") != bucket:
                continue
            value = row.get(metric)
            if isinstance(value, (int, float)):
                values.append(float(value))
        return values

    def metric_block(metric: str, bucket: str | None = None) -> dict:
        values = collect(metric, bucket=bucket)
        return {
            "count": len(values),
            "mean_ms": round(statistics.fmean(values), 2) if values else None,
            "p50_ms": round(percentile(values, 0.50), 2) if values else None,
            "p95_ms": round(percentile(values, 0.95), 2) if values else None,
            "max_ms": round(max(values), 2) if values else None,
        }

    buckets = sorted({row["bucket"] for row in rows})
    summary = {
        "total_samples": len(rows),
        "latency_ms": metric_block("total_latency_ms"),
        "first_token_latency_ms": metric_block("first_token_latency_ms"),
        "buckets": {},
    }
    llm_latency = metric_block("llm_total_latency_ms")
    if llm_latency["count"] > 0:
        summary["llm_latency_ms"] = llm_latency

    for bucket in buckets:
        bucket_summary = {
            "samples": sum(1 for row in rows if row.get("bucket") == bucket),
            "latency_ms": metric_block("total_latency_ms", bucket=bucket),
            "first_token_latency_ms": metric_block("first_token_latency_ms", bucket=bucket),
        }
        llm_bucket_latency = metric_block("llm_total_latency_ms", bucket=bucket)
        if llm_bucket_latency["count"] > 0:
            bucket_summary["llm_latency_ms"] = llm_bucket_latency
        summary["buckets"][bucket] = bucket_summary

    rss_values = [row["rss_after_kb"] for row in rows if isinstance(row.get("rss_after_kb"), int)]
    if rss_values:
        summary["rss_after_kb"] = {
            "max": max(rss_values),
            "mean": round(statistics.fmean(rss_values), 2),
        }

    # Quality metrics: exact match and period-tolerant match
    total_rows = len(rows)
    completed_count = 0
    exact_matches = 0
    period_matches = 0
    error_count = sum(1 for row in rows if "error" in row)
    failures: list[dict] = []
    for row in rows:
        expected = row.get("expected")
        output = row.get("output")
        error = row.get("error")

        if error is not None:
            failures.append({
                "id": row.get("id", "?"),
                "bucket": row.get("bucket", "?"),
                "expected": expected,
                "error": error,
            })
            continue

        if expected is None or output is None:
            failures.append({
                "id": row.get("id", "?"),
                "bucket": row.get("bucket", "?"),
                "expected": expected,
                "output": output,
                "error": "missing_expected_or_output",
            })
            continue

        completed_count += 1
        if output == expected:
            exact_matches += 1
            period_matches += 1
        elif output.rstrip(".") == expected.rstrip("."):
            period_matches += 1
        else:
            failures.append({
                "id": row.get("id", "?"),
                "bucket": row.get("bucket", "?"),
                "expected": expected,
                "output": output,
            })

    if total_rows > 0:
        summary["quality"] = {
            "total": total_rows,
            "completed": completed_count,
            "completed_pct": round(100.0 * completed_count / total_rows, 1),
            "errors": error_count,
            "error_pct": round(100.0 * error_count / total_rows, 1),
            "exact_match": exact_matches,
            "exact_match_pct": round(100.0 * exact_matches / total_rows, 1),
            "completed_exact_match_pct": (
                round(100.0 * exact_matches / completed_count, 1) if completed_count else None
            ),
            "period_tolerant_match": period_matches,
            "period_tolerant_pct": round(100.0 * period_matches / total_rows, 1),
            "completed_period_tolerant_pct": (
                round(100.0 * period_matches / completed_count, 1) if completed_count else None
            ),
            "failures": failures,
        }

        # Per-bucket quality
        for bucket in buckets:
            bucket_rows = [r for r in rows if r.get("bucket") == bucket]
            b_total = len(bucket_rows)
            b_completed = 0
            b_errors = sum(1 for r in bucket_rows if "error" in r)
            b_period = 0
            for r in bucket_rows:
                exp = r.get("expected")
                out = r.get("output")
                if exp is None or out is None:
                    continue
                b_completed += 1
                if out == exp or out.rstrip(".") == exp.rstrip("."):
                    b_period += 1
            if b_total > 0:
                summary["buckets"][bucket]["period_tolerant_pct"] = round(
                    100.0 * b_period / b_total, 1
                )
                summary["buckets"][bucket]["completed_pct"] = round(
                    100.0 * b_completed / b_total, 1
                )
                summary["buckets"][bucket]["error_pct"] = round(
                    100.0 * b_errors / b_total, 1
                )

    path_counts: dict[str, int] = {}
    for row in rows:
        path = row.get("normalization_path")
        if isinstance(path, str):
            path_counts[path] = path_counts.get(path, 0) + 1
    if path_counts:
        summary["normalization_paths"] = path_counts

    return summary


def main() -> int:
    helper: FullPipelineHelper | None = None
    try:
        args = parse_args()
        effective_super_style = resolve_super_style(args)
        dataset_path = Path(args.dataset)
        output_path = Path(args.output)
        summary_path = Path(args.summary)

        output_path.parent.mkdir(parents=True, exist_ok=True)
        summary_path.parent.mkdir(parents=True, exist_ok=True)

        dataset = load_dataset(dataset_path)
        validate_expected_key(dataset, args.expected_key)

        if args.pipeline_mode == "full-pipeline":
            helper_binary = ensure_full_pipeline_helper(HELPER_BINARY)
            helper = FullPipelineHelper(helper_binary)

        system_prompt, prompt_source = resolve_system_prompt(
            args=args,
            helper=helper,
            effective_super_style=effective_super_style,
        )
        prompt_hash = prompt_sha256(system_prompt)

        print(f"Loaded {len(dataset)} samples from {dataset_path}")
        print(f"Pipeline mode: {args.pipeline_mode}")
        if args.pipeline_mode == "full-pipeline":
            print(f"Super style: {effective_super_style}")
        if system_prompt:
            print(f"Using system prompt from {prompt_source}")
            print(f"Prompt SHA-256: {prompt_hash}")
        if args.system_prompt_file:
            print(
                "WARNING: --system-prompt-file overrides the current production prompt.",
                file=sys.stderr,
            )

        stop_sequences = None
        if args.stop:
            try:
                stop_sequences = [s.encode().decode("unicode_escape") for s in args.stop]
            except (UnicodeDecodeError, ValueError) as exc:
                raise BenchmarkConfigurationError(f"Invalid stop sequence format: {exc}") from exc

        recorded_rows: list[dict] = []
        with output_path.open("w", encoding="utf-8") as output_file:
            for index, sample in enumerate(dataset):
                sample_id = str(sample.get("id", "?"))
                input_text = sample["input"]
                rss_before_kb = read_rss_kb(args.server_pid)
                expected_key, expected_value = resolve_expected(sample, args)
                pipeline_start = time.perf_counter()

                result = {
                    **sample,
                    "expected": expected_value,
                    "expected_key": expected_key,
                }

                if args.pipeline_mode == "full-pipeline":
                    full_pipeline_helper = require_full_pipeline_helper(helper)
                    try:
                        preflight = full_pipeline_helper.request({
                            "op": "preflight",
                            "transcript": input_text,
                            "terminalPeriodEnabled": not args.no_terminal_period,
                        })
                    except FullPipelineHelperError as exc:
                        raise type(exc)(
                            f"[{sample_id}] Full-pipeline helper failed during preflight: {exc}"
                        ) from exc

                    deterministic_text = preflight["deterministicText"]
                    should_invoke_llm = bool(preflight["shouldInvokeLLM"])
                    result["deterministic_input"] = deterministic_text

                    if not should_invoke_llm:
                        total_latency_ms = (time.perf_counter() - pipeline_start) * 1000.0
                        result.update({
                            "output": deterministic_text,
                            "normalization_path": "trivial",
                            "llm_total_latency_ms": None,
                            "first_token_latency_ms": None,
                            "total_latency_ms": round(total_latency_ms, 2),
                            "rss_before_kb": rss_before_kb,
                            "rss_after_kb": read_rss_kb(args.server_pid),
                        })
                    else:
                        try:
                            llm_output, first_token_ms, llm_total_latency_ms = request_completion(
                                base_url=args.base_url,
                                model=args.model,
                                user_text=deterministic_text,
                                system_prompt=system_prompt,
                                timeout=args.timeout,
                                max_tokens=args.max_tokens,
                                temperature=args.temperature,
                                stop=stop_sequences,
                            )
                        except LLMRequestError as exc:
                            try:
                                postflight = full_pipeline_helper.request({
                                    "op": "failed-postflight",
                                    "deterministicText": deterministic_text,
                                    "failureContext": str(exc),
                                })
                            except FullPipelineHelperError as helper_exc:
                                raise type(helper_exc)(
                                    f"[{sample_id}] LLM request failed with '{exc}', "
                                    f"then full-pipeline helper failed during failed-postflight: {helper_exc}"
                                ) from helper_exc

                            total_latency_ms = (time.perf_counter() - pipeline_start) * 1000.0
                            result.update({
                                "output": postflight["finalText"],
                                "normalization_path": postflight["normalizationPath"],
                                "failure_context": postflight.get("failureContext"),
                                "llm_total_latency_ms": None,
                                "first_token_latency_ms": None,
                                "total_latency_ms": round(total_latency_ms, 2),
                                "rss_before_kb": rss_before_kb,
                                "rss_after_kb": read_rss_kb(args.server_pid),
                                "error": str(exc),
                            })
                            output_file.write(json.dumps(result, ensure_ascii=False) + "\n")
                            print(
                                f"[{index + 1}/{len(dataset)}] {sample_id}: ERROR {exc}",
                                file=sys.stderr,
                            )
                            if index >= args.warmup:
                                recorded_rows.append(result)
                            continue

                        try:
                            postflight = full_pipeline_helper.request({
                                "op": "postflight",
                                "deterministicText": deterministic_text,
                                "llmOutput": llm_output,
                                "superStyle": effective_super_style,
                                "terminalPeriodEnabled": not args.no_terminal_period,
                            })
                        except FullPipelineHelperError as exc:
                            raise type(exc)(
                                f"[{sample_id}] Full-pipeline helper failed during postflight: {exc}"
                            ) from exc

                        total_latency_ms = (time.perf_counter() - pipeline_start) * 1000.0
                        result.update({
                            "llm_output": llm_output,
                            "output": postflight["finalText"],
                            "normalization_path": postflight["normalizationPath"],
                            "gate_failure_reason": postflight.get("gateFailureReason"),
                            "failure_context": postflight.get("failureContext"),
                            "llm_total_latency_ms": round(llm_total_latency_ms, 2),
                            "first_token_latency_ms": (
                                round(first_token_ms, 2) if first_token_ms is not None else None
                            ),
                            "total_latency_ms": round(total_latency_ms, 2),
                            "rss_before_kb": rss_before_kb,
                            "rss_after_kb": read_rss_kb(args.server_pid),
                        })
                else:
                    try:
                        output_text, first_token_ms, total_latency_ms = request_completion(
                            base_url=args.base_url,
                            model=args.model,
                            user_text=input_text,
                            system_prompt=system_prompt,
                            timeout=args.timeout,
                            max_tokens=args.max_tokens,
                            temperature=args.temperature,
                            stop=stop_sequences,
                        )
                    except LLMRequestError as exc:
                        result.update({
                            "error": str(exc),
                            "rss_before_kb": rss_before_kb,
                            "rss_after_kb": read_rss_kb(args.server_pid),
                        })
                        output_file.write(json.dumps(result, ensure_ascii=False) + "\n")
                        print(
                            f"[{index + 1}/{len(dataset)}] {sample_id}: ERROR {exc}",
                            file=sys.stderr,
                        )
                        if index >= args.warmup:
                            recorded_rows.append(result)
                        continue

                    result.update({
                        "output": output_text,
                        "first_token_latency_ms": (
                            round(first_token_ms, 2) if first_token_ms is not None else None
                        ),
                        "total_latency_ms": round(total_latency_ms, 2),
                        "rss_before_kb": rss_before_kb,
                        "rss_after_kb": read_rss_kb(args.server_pid),
                    })

                output_file.write(json.dumps(result, ensure_ascii=False) + "\n")

                label = "warmup" if index < args.warmup else "recorded"
                print(
                    f"[{index + 1}/{len(dataset)}] {sample_id} "
                    f"{label} total={result['total_latency_ms']}ms "
                    f"first={result.get('first_token_latency_ms')}ms "
                    f"path={result.get('normalization_path', 'llm-only')}"
                )

                if index >= args.warmup:
                    recorded_rows.append(result)

        summary = summarize(recorded_rows)
        summary.update(
            {
                "dataset": str(dataset_path),
                "model": args.model,
                "base_url": args.base_url,
                "warmup": args.warmup,
                "pipeline_mode": args.pipeline_mode,
                "super_style": effective_super_style if args.pipeline_mode == "full-pipeline" else None,
                "legacy_text_mode": args.text_mode,
                "prompt_source": prompt_source,
                "prompt_sha256": prompt_hash,
                "prompt_override": bool(args.system_prompt_file),
                "expected_key": args.expected_key or (
                    "expected_full_pipeline_or_expected"
                    if args.pipeline_mode == "full-pipeline"
                    else "expected"
                ),
            }
        )

        summary_path.write_text(
            json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )

        print(f"\nSaved raw results to {output_path}")
        print(f"Saved summary to {summary_path}")

        quality = summary.get("quality")
        if quality:
            print(f"\n{'='*60}")
            print(f"QUALITY: {quality['period_tolerant_pct']}% period-tolerant match "
                  f"end-to-end ({quality['period_tolerant_match']}/{quality['total']})")
            print(f"         {quality['exact_match_pct']}% exact match "
                  f"end-to-end ({quality['exact_match']}/{quality['total']})")
            print(f"         {quality['completed_pct']}% completed "
                  f"({quality['completed']}/{quality['total']}), "
                  f"errors={quality['errors']}")
            for bucket_name in sorted(summary.get("buckets", {})):
                pct = summary["buckets"][bucket_name].get("period_tolerant_pct", "?")
                cnt = summary["buckets"][bucket_name].get("samples", "?")
                print(f"  {bucket_name:8s}: {pct}% ({cnt} samples)")
            if quality["failures"]:
                print(f"\nFAILURES ({len(quality['failures'])}):")
                for f in quality["failures"]:
                    print(f"  [{f['id']}] {f['bucket']}")
                    if "error" in f:
                        print(f"    error:    {f['error']}")
                        if f.get("expected") is not None:
                            print(f"    expected: {f['expected']}")
                    else:
                        print(f"    expected: {f['expected']}")
                        print(f"    got:      {f['output']}")
            print(f"{'='*60}")
        else:
            print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 0
    except BenchmarkError as exc:
        fail(str(exc))
        return 1
    except Exception as exc:  # noqa: BLE001
        fail(f"Unexpected benchmark error: {exc}")
        return 1
    finally:
        if helper is not None:
            helper.close()


if __name__ == "__main__":
    raise SystemExit(main())
