#!/usr/bin/env python3

import argparse
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
        default=192,
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
    return parser.parse_args()


def load_dataset(path: Path) -> list[dict]:
    rows: list[dict] = []
    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def load_system_prompt(path: str | None) -> str | None:
    if not path:
        return None
    return Path(path).read_text(encoding="utf-8").strip()


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

                chunk = json.loads(data)
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
        raise RuntimeError(f"HTTP {exc.code}: {body}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"Connection error: {exc}") from exc

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

    for bucket in buckets:
        summary["buckets"][bucket] = {
            "samples": sum(1 for row in rows if row.get("bucket") == bucket),
            "latency_ms": metric_block("total_latency_ms", bucket=bucket),
            "first_token_latency_ms": metric_block("first_token_latency_ms", bucket=bucket),
        }

    rss_values = [row["rss_after_kb"] for row in rows if isinstance(row.get("rss_after_kb"), int)]
    if rss_values:
        summary["rss_after_kb"] = {
            "max": max(rss_values),
            "mean": round(statistics.fmean(rss_values), 2),
        }

    # Quality metrics: exact match and period-tolerant match
    total_with_expected = 0
    exact_matches = 0
    period_matches = 0
    failures: list[dict] = []
    for row in rows:
        expected = row.get("expected")
        output = row.get("output")
        if expected is None or output is None:
            continue
        total_with_expected += 1
        if output == expected:
            exact_matches += 1
            period_matches += 1
        elif output + "." == expected or output + "." == expected.rstrip(".") + ".":
            period_matches += 1
        else:
            failures.append({
                "id": row.get("id", "?"),
                "bucket": row.get("bucket", "?"),
                "expected": expected,
                "output": output,
            })

    if total_with_expected > 0:
        summary["quality"] = {
            "total": total_with_expected,
            "exact_match": exact_matches,
            "exact_match_pct": round(100.0 * exact_matches / total_with_expected, 1),
            "period_tolerant_match": period_matches,
            "period_tolerant_pct": round(100.0 * period_matches / total_with_expected, 1),
            "failures": failures,
        }

        # Per-bucket quality
        for bucket in buckets:
            bucket_rows = [r for r in rows if r.get("bucket") == bucket]
            b_total = 0
            b_period = 0
            for r in bucket_rows:
                exp = r.get("expected")
                out = r.get("output")
                if exp is None or out is None:
                    continue
                b_total += 1
                if out == exp or out + "." == exp or out + "." == exp.rstrip(".") + ".":
                    b_period += 1
            if b_total > 0:
                summary["buckets"][bucket]["period_tolerant_pct"] = round(
                    100.0 * b_period / b_total, 1
                )

    return summary


def main() -> int:
    args = parse_args()
    dataset_path = Path(args.dataset)
    output_path = Path(args.output)
    summary_path = Path(args.summary)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.parent.mkdir(parents=True, exist_ok=True)

    dataset = load_dataset(dataset_path)
    system_prompt = load_system_prompt(args.system_prompt_file)

    print(f"Loaded {len(dataset)} samples from {dataset_path}")
    if system_prompt:
        print(f"Using system prompt from {args.system_prompt_file}")

    recorded_rows: list[dict] = []
    with output_path.open("w", encoding="utf-8") as output_file:
        for index, sample in enumerate(dataset):
            rss_before_kb = read_rss_kb(args.server_pid)

            stop_sequences = None
            if args.stop:
                stop_sequences = [s.encode().decode("unicode_escape") for s in args.stop]

            try:
                output_text, first_token_ms, total_latency_ms = request_completion(
                    base_url=args.base_url,
                    model=args.model,
                    user_text=sample["input"],
                    system_prompt=system_prompt,
                    timeout=args.timeout,
                    max_tokens=args.max_tokens,
                    temperature=args.temperature,
                    stop=stop_sequences,
                )
            except Exception as exc:  # noqa: BLE001
                result = {
                    **sample,
                    "error": str(exc),
                    "rss_before_kb": rss_before_kb,
                    "rss_after_kb": read_rss_kb(args.server_pid),
                }
                output_file.write(json.dumps(result, ensure_ascii=False) + "\n")
                print(f"[{index + 1}/{len(dataset)}] {sample['id']}: ERROR {exc}", file=sys.stderr)
                continue

            rss_after_kb = read_rss_kb(args.server_pid)
            result = {
                **sample,
                "output": output_text,
                "first_token_latency_ms": round(first_token_ms, 2) if first_token_ms is not None else None,
                "total_latency_ms": round(total_latency_ms, 2),
                "rss_before_kb": rss_before_kb,
                "rss_after_kb": rss_after_kb,
            }
            output_file.write(json.dumps(result, ensure_ascii=False) + "\n")

            label = "warmup" if index < args.warmup else "recorded"
            print(
                f"[{index + 1}/{len(dataset)}] {sample['id']} "
                f"{label} total={result['total_latency_ms']}ms "
                f"first={result['first_token_latency_ms']}ms"
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
        }
    )

    summary_path.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"\nSaved raw results to {output_path}")
    print(f"Saved summary to {summary_path}")

    # Print quality report
    quality = summary.get("quality")
    if quality:
        print(f"\n{'='*60}")
        print(f"QUALITY: {quality['period_tolerant_pct']}% period-tolerant match "
              f"({quality['period_tolerant_match']}/{quality['total']})")
        print(f"         {quality['exact_match_pct']}% exact match "
              f"({quality['exact_match']}/{quality['total']})")
        for bucket_name in sorted(summary.get("buckets", {})):
            pct = summary["buckets"][bucket_name].get("period_tolerant_pct", "?")
            cnt = summary["buckets"][bucket_name].get("samples", "?")
            print(f"  {bucket_name:8s}: {pct}% ({cnt} samples)")
        if quality["failures"]:
            print(f"\nFAILURES ({len(quality['failures'])}):")
            for f in quality["failures"]:
                print(f"  [{f['id']}] {f['bucket']}")
                print(f"    expected: {f['expected']}")
                print(f"    got:      {f['output']}")
        print(f"{'='*60}")
    else:
        print(json.dumps(summary, ensure_ascii=False, indent=2))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
