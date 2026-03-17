#!/bin/bash
set -euo pipefail

# Скачать все Python wheels для офлайн установки на macOS arm64 + universal2 + any.
# Запускать РАЗРАБОТЧИКОМ перед сборкой DMG, не пользователем.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WHEELS_DIR="$SCRIPT_DIR/../worker/wheels"
REQUIREMENTS="$SCRIPT_DIR/../worker/requirements.txt"
PYTHON="${PYTHON:-python3}"

rm -rf "$WHEELS_DIR"
mkdir -p "$WHEELS_DIR"

echo "==> Скачиваю wheels из requirements.txt..."
"$PYTHON" -m pip download \
    -r "$REQUIREMENTS" \
    --dest "$WHEELS_DIR" \
    --implementation cp \
    --abi cp313 \
    --python-version 3.13 \
    --platform macosx_14_0_arm64 \
    --platform macosx_13_0_arm64 \
    --platform macosx_12_0_arm64 \
    --platform macosx_11_0_arm64 \
    --platform macosx_14_0_universal2 \
    --platform macosx_10_9_universal2 \
    --platform any \
    --only-binary=:all: \
    --no-cache-dir

# setuptools — транзитивная зависимость torch (через silero-vad), обязательна на Python 3.12+
echo "==> Скачиваю setuptools..."
"$PYTHON" -m pip download setuptools \
    --dest "$WHEELS_DIR" \
    --python-version 3.13 \
    --platform any \
    --only-binary=:all: \
    --no-cache-dir

COUNT=$(ls "$WHEELS_DIR"/*.whl 2>/dev/null | wc -l | tr -d ' ')
SIZE=$(du -sh "$WHEELS_DIR" | cut -f1)

# Валидация: минимум столько wheels сколько строк в requirements.txt
EXPECTED=$(grep -cve '^\s*$' "$REQUIREMENTS")
if [ "$COUNT" -lt "$EXPECTED" ]; then
    echo "ERROR: Скачано $COUNT wheels, ожидалось >= $EXPECTED" >&2
    echo "Проверьте что pip download не пропустил пакеты" >&2
    exit 1
fi

echo ""
echo "==> Скачано $COUNT wheels в worker/wheels/ ($SIZE)"
ls -1 "$WHEELS_DIR"/*.whl 2>/dev/null | while read -r f; do echo "    $(basename "$f")"; done
echo ""
echo "Следующий шаг: xcodebuild build (wheels попадут в bundle через copyFiles в project.yml)"
