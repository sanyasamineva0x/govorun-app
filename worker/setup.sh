#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# venv живёт в ~/.govorun/venv/ — не пересоздаётся при каждом билде Xcode
VENV_DIR="$HOME/.govorun/venv"
WHEELS_DIR="$SCRIPT_DIR/wheels"

# Принимать путь к Python как аргумент (передаётся из Swift)
PYTHON="${1:-python3}"

if ! command -v "$PYTHON" &> /dev/null && ! [ -x "$PYTHON" ]; then
    echo "ERROR: python3 не найден ($PYTHON). Установите: xcode-select --install" >&2
    exit 1
fi

# Пересоздать venv если Python версия не совпадает (например 3.9 → 3.13)
EXPECTED_VER=$("$PYTHON" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>&1)
if [ $? -ne 0 ]; then
    echo "ERROR: не удалось определить версию Python ($PYTHON): $EXPECTED_VER" >&2
    exit 1
fi
VENV_VER=$("$VENV_DIR/bin/python3" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "none")

if [ ! -d "$VENV_DIR" ] || [ "$VENV_VER" != "$EXPECTED_VER" ]; then
    [ -d "$VENV_DIR" ] && echo "Python версия изменилась ($VENV_VER → $EXPECTED_VER), пересоздаю venv..."
    rm -rf "$VENV_DIR"
    if [ -d "$VENV_DIR" ]; then
        echo "ERROR: не удалось удалить $VENV_DIR — проверьте права доступа" >&2
        exit 1
    fi
    "$PYTHON" -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

if [ -d "$WHEELS_DIR" ] && ls "$WHEELS_DIR"/*.whl 1>/dev/null 2>&1; then
    # Офлайн: wheels найдены (DMG-дистрибуция или dev после download-wheels.sh)
    COUNT=$(ls "$WHEELS_DIR"/*.whl | wc -l | tr -d ' ')
    echo "Офлайн установка: $COUNT wheels из $WHEELS_DIR"
    pip install --no-index --find-links="$WHEELS_DIR" -r "$SCRIPT_DIR/requirements.txt"
elif [ -d "$WHEELS_DIR" ]; then
    # wheels/ существует но пуст — битый bundle
    echo "ERROR: wheels/ пуст. Запустите: bash scripts/download-wheels.sh" >&2
    exit 1
else
    # wheels/ нет — Xcode Debug build или dev без vendored wheels
    echo "WARN: wheels/ не найден, устанавливаю из PyPI" >&2
    pip install -q -r "$SCRIPT_DIR/requirements.txt"
fi

echo "SETUP_DONE"
