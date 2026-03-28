#!/usr/bin/env bash
set -euo pipefail

MODEL_PATH="${MODEL_PATH:-${1:-}}"
PORT="${PORT:-8080}"
HOST="${HOST:-127.0.0.1}"
MODEL_ALIAS="${MODEL_ALIAS:-gigachat-gguf}"
CTX_SIZE="${CTX_SIZE:-4096}"
GPU_LAYERS="${GPU_LAYERS:--1}"

if [[ -z "$MODEL_PATH" ]]; then
  echo "usage: MODEL_PATH=/path/to/gigachat.gguf bash scripts/run-gigachat-llm.sh"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

if [[ -x "$PROJECT_DIR/Helpers/llama-server" ]]; then
  LLAMA_SERVER_BIN="$PROJECT_DIR/Helpers/llama-server"
elif command -v llama-server >/dev/null 2>&1; then
  LLAMA_SERVER_BIN="$(command -v llama-server)"
  echo "WARN: используется PATH llama-server (может быть динамически слинкован). Для prod: bash scripts/build-llama-server.sh" >&2
elif [[ -x "$PROJECT_DIR/.build-llama-server/build/bin/llama-server" ]]; then
  LLAMA_SERVER_BIN="$PROJECT_DIR/.build-llama-server/build/bin/llama-server"
  echo "WARN: используется build-temp binary (без codesign). Скопируйте: cp .build-llama-server/build/bin/llama-server Helpers/" >&2
else
  echo "llama-server not found. Run: bash scripts/build-llama-server.sh"
  exit 1
fi

echo "[Govorun] Starting local GigaChat endpoint on http://${HOST}:${PORT}/v1"
echo "[Govorun] Binary: ${LLAMA_SERVER_BIN}"
echo "[Govorun] Model: ${MODEL_PATH}"
echo "[Govorun] Alias: ${MODEL_ALIAS}"

exec "$LLAMA_SERVER_BIN" \
  --host "$HOST" \
  --port "$PORT" \
  --model "$MODEL_PATH" \
  --alias "$MODEL_ALIAS" \
  --ctx-size "$CTX_SIZE" \
  --n-gpu-layers "$GPU_LAYERS"
