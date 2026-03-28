#!/bin/bash
set -euo pipefail

# Сборка статического llama-server (arm64) для бандлинга в Govorun.app.
# Результат: Helpers/llama-server — один бинарник, без сторонних зависимостей (только системные фреймворки).

LLAMA_CPP_TAG="b8500"  # проверено с GigaChat 3.1 Q4_K_M
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/Helpers"
OUTPUT_BIN="$OUTPUT_DIR/llama-server"
BUILD_TMP="$PROJECT_DIR/.build-llama-server"
trap 'rc=$?; rm -rf "$BUILD_TMP"; [ $rc -ne 0 ] && rm -f "$OUTPUT_BIN"; exit $rc' EXIT

if [ -f "$OUTPUT_BIN" ]; then
    echo "llama-server уже собран в $OUTPUT_BIN"
    if ! "$OUTPUT_BIN" --version 2>&1 | head -1; then
        echo "WARN: кешированный бинарник не запускается, пересобираю..." >&2
        rm -f "$OUTPUT_BIN"
    elif otool -L "$OUTPUT_BIN" | tail -n +2 | awk '{print $1}' | grep -qvE '^(/System/Library/Frameworks/|/usr/lib/)'; then
        echo "WARN: кешированный бинарник имеет несистемные зависимости, пересобираю..." >&2
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
    -DLLAMA_CURL=OFF \
    -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=ON

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
DEPS=$(otool -L "$OUTPUT_BIN" | tail -n +2 | awk '{print $1}')
echo "$DEPS"

# Allowlist: только системные фреймворки и библиотеки
ALLOWED_PREFIXES="/System/Library/Frameworks/ /usr/lib/"
BAD_DEPS=""
while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    ok=false
    for prefix in $ALLOWED_PREFIXES; do
        case "$dep" in "$prefix"*) ok=true; break;; esac
    done
    if ! $ok; then
        BAD_DEPS="$BAD_DEPS  $dep\n"
    fi
done <<< "$DEPS"

if [ -n "$BAD_DEPS" ]; then
    echo "ERROR: бинарник зависит от несистемных библиотек:" >&2
    echo -e "$BAD_DEPS" >&2
    exit 1
fi

SIZE=$(du -h "$OUTPUT_BIN" | cut -f1)
echo ""
echo "==> llama-server готов ($SIZE)"
echo "    $OUTPUT_BIN"
