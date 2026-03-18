#!/bin/bash
set -euo pipefail

# Сборка unsigned DMG для open source дистрибуции.
# Не требует Apple Developer ID. Homebrew снимает quarantine при установке.

APP_NAME="Говорун"
SCHEME="Govorun"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/Govorun.xcarchive"
APP="$BUILD_DIR/Govorun.app"
DMG="$BUILD_DIR/Govorun.dmg"

echo "==> Очистка build/"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 1. Archive (Copy Files phase копирует Python.framework + worker)
echo "==> Архивирование..."
xcodebuild archive \
  -scheme "$SCHEME" \
  -archivePath "$ARCHIVE" \
  -destination 'generic/platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  -quiet

# Достать .app из archive (без exportArchive — он требует Developer ID)
ARCHIVED_APP="$ARCHIVE/Products/Applications/Govorun.app"
if [ ! -d "$ARCHIVED_APP" ]; then
    # Попробовать альтернативный путь
    ARCHIVED_APP=$(find "$ARCHIVE" -name "Govorun.app" -type d | head -1)
fi
if [ -z "$ARCHIVED_APP" ] || [ ! -d "$ARCHIVED_APP" ]; then
    echo "ERROR: Govorun.app не найден в archive" >&2
    exit 1
fi
cp -R "$ARCHIVED_APP" "$APP"

# Гарантированное копирование Python.framework (xcodebuild с objectVersion 56 может пропустить)
if [ ! -d "Frameworks/Python.framework" ]; then
    echo "ERROR: Frameworks/Python.framework не найден. Запустите: bash scripts/fetch-python-framework.sh" >&2
    exit 1
fi
echo "==> Копирую Python.framework в bundle..."
rm -rf "$APP/Contents/Frameworks/Python.framework"
mkdir -p "$APP/Contents/Frameworks"
cp -R "Frameworks/Python.framework" "$APP/Contents/Frameworks/"

# Worker файлы — гарантированно копируем (objectVersion 56 может не скопировать)
echo "==> Копирую worker файлы в bundle..."
mkdir -p "$APP/Contents/Resources/worker"
for f in server.py setup.sh requirements.txt VERSION; do
    cp "worker/$f" "$APP/Contents/Resources/worker/"
done
chmod +x "$APP/Contents/Resources/worker/setup.sh"

# Wheels для офлайн установки
if [ -d "worker/wheels" ] && ls worker/wheels/*.whl 1>/dev/null 2>&1; then
    echo "==> Копирую wheels в bundle..."
    mkdir -p "$APP/Contents/Resources/worker/wheels"
    cp worker/wheels/*.whl "$APP/Contents/Resources/worker/wheels/"
else
    echo "WARN: worker/wheels не найден. DMG будет требовать интернет при первом запуске." >&2
fi

# 2. Ad-hoc подпись (без Developer ID, но macOS требует подпись)
echo "==> Ad-hoc подпись..."
if [ -d "$APP/Contents/Frameworks/Python.framework" ]; then
    echo "    Python.framework..."
    find "$APP/Contents/Frameworks/Python.framework" -type f \( -name "*.so" -o -name "*.dylib" \) \
        -exec codesign --force --sign - {} \; 2>/dev/null || true
    for bin in "$APP/Contents/Frameworks/Python.framework/Versions/3.13/bin/python3.13" \
               "$APP/Contents/Frameworks/Python.framework/Versions/3.13/Python"; do
        [ -f "$bin" ] && codesign --force --sign - "$bin" 2>/dev/null || true
    done
    codesign --force --sign - "$APP/Contents/Frameworks/Python.framework" 2>/dev/null || true
fi
codesign --force --sign - --entitlements "Govorun/Govorun.entitlements" "$APP"

# 3. DMG
echo "==> Создание DMG..."
hdiutil create -volname "$APP_NAME" \
  -srcfolder "$APP" \
  -ov -format UDZO \
  "$DMG"

echo ""
echo "==> $DMG готов"
echo "    Размер: $(du -h "$DMG" | cut -f1)"
echo ""
echo "Установка: brew tap sanyasamineva0x/govorun && brew install --cask govorun"
echo "Или вручную: открыть DMG → перетащить в Applications → правый клик → Открыть"
