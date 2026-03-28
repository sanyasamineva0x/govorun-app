#!/bin/bash
set -euo pipefail

# Сборка статического llama-server (arm64) для бандлинга в Govorun.app.
# Результат: Helpers/llama-server — один бинарник, zero внешних deps.

LLAMA_CPP_TAG="b8500"  # проверено с GigaChat 3.1 Q4_K_M
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/Helpers"
OUTPUT_BIN="$OUTPUT_DIR/llama-server"
BUILD_TMP="$PROJECT_DIR/.build-llama-server"
trap 'rm -rf "$BUILD_TMP"' EXIT

if [ -f "$OUTPUT_BIN" ]; then
    echo "llama-server уже собран в $OUTPUT_BIN"
    "$OUTPUT_BIN" --version 2>&1 | head -1 || true
    if otool -L "$OUTPUT_BIN" | tail -n +2 | grep -q "homebrew\|/usr/local/\|/opt/homebrew/"; then
        echo "WARN: кешированный бинарник динамически слинкован, пересобираю..." >&2
        rm -f "$OUTPUT_BIN"
    else
        exit 0
    fi
fi

for cmd in cmake git codesign otool sysctl; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd не найден" >&2; exit 1; }
done

echo "==> Клонирую llama.cpp @ $LLAMA_CPP_TAG..."
rm -rf "$BUILD_TMP"
git clone --depth 1 --branch "$LLAMA_CPP_TAG" \
    https://github.com/ggerganov/llama.cpp "$BUILD_TMP/llama.cpp"

echo "==> Собираю статический llama-server (arm64)..."
cmake -S "$BUILD_TMP/llama.cpp" -B "$BUILD_TMP/build" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DGGML_BLAS=ON \
    -DGGML_BLAS_VENDOR=Apple \
    -DLLAMA_CURL=OFF

cmake --build "$BUILD_TMP/build" --target llama-server -j"$(sysctl -n hw.ncpu)"

if [ ! -f "$BUILD_TMP/build/bin/llama-server" ]; then
    echo "ERROR: cmake сборка не создала бинарник" >&2
    exit 1
fi

echo "==> Копирую в $OUTPUT_BIN..."
mkdir -p "$OUTPUT_DIR"
cp "$BUILD_TMP/build/bin/llama-server" "$OUTPUT_BIN"

echo "==> Ad-hoc подпись..."
codesign --force --sign - "$OUTPUT_BIN"

echo "==> Проверка зависимостей..."
DEPS=$(otool -L "$OUTPUT_BIN" | tail -n +2)
echo "$DEPS"

# Проверяем что нет brew/homebrew зависимостей
if echo "$DEPS" | grep -q "homebrew\|/usr/local/\|/opt/homebrew/"; then
    echo "ERROR: бинарник зависит от brew библиотек!" >&2
    exit 1
fi

echo "==> Очистка..."
rm -rf "$BUILD_TMP"

SIZE=$(du -h "$OUTPUT_BIN" | cut -f1)
echo ""
echo "==> llama-server готов ($SIZE)"
echo "    $OUTPUT_BIN"
