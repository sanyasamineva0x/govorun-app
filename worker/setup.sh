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

if [ ! -d "$VENV_DIR" ]; then
    echo "Создаю виртуальное окружение..."
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
