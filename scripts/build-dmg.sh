#!/bin/bash
set -euo pipefail

APP_NAME="Говорун"
SCHEME="Govorun"
TEAM_ID="${TEAM_ID:-XXXXXXXXXX}"          # Apple Developer Team ID
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application: Your Name ($TEAM_ID)}"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-govorun-notary}"  # xcrun notarytool store-credentials

# Валидация: не запускать с placeholder значениями
if [[ "$TEAM_ID" == "XXXXXXXXXX" ]] && [[ "$SIGNING_IDENTITY" == *"Your Name"* ]]; then
    echo "ERROR: Укажите TEAM_ID и SIGNING_IDENTITY:" >&2
    echo "  TEAM_ID=ABC123 SIGNING_IDENTITY='Developer ID Application: ...' ./scripts/build-dmg.sh" >&2
    exit 1
fi

BUILD_DIR="build"
# ASCII paths для сборки (Cyrillic только в DMG volume name)
ARCHIVE="$BUILD_DIR/Govorun.xcarchive"
APP="$BUILD_DIR/Govorun.app"
DMG="$BUILD_DIR/$APP_NAME.dmg"

echo "==> Очистка build/"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 1. Archive
echo "==> Архивирование..."
xcodebuild archive \
  -scheme "$SCHEME" \
  -archivePath "$ARCHIVE" \
  -destination 'generic/platform=macOS' \
  -quiet

# 2. Export
echo "==> Экспорт..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$BUILD_DIR" \
  -exportOptionsPlist ExportOptions.plist

# Найти .app в build/ (имя может быть Govorun.app)
EXPORTED_APP=$(find "$BUILD_DIR" -name "*.app" -maxdepth 1 | head -1)
if [ -z "$EXPORTED_APP" ]; then
    echo "ERROR: .app не найден в $BUILD_DIR" >&2
    exit 1
fi
# Переименовать если нужно
if [ "$EXPORTED_APP" != "$APP" ]; then
    mv "$EXPORTED_APP" "$APP"
fi

# 3. Codesign inside-out: сначала embedded frameworks, потом .app
echo "==> Подпись..."

# Python.framework: подписать все .so, .dylib, бинарники, потом сам framework
if [ -d "$APP/Contents/Frameworks/Python.framework" ]; then
    echo "    Подпись Python.framework..."
    find "$APP/Contents/Frameworks/Python.framework" -type f \( -name "*.so" -o -name "*.dylib" \) \
        -exec codesign --force --options runtime --sign "$SIGNING_IDENTITY" {} \;
    # Бинарники
    for bin in "$APP/Contents/Frameworks/Python.framework/Versions/3.13/bin/python3.13" \
               "$APP/Contents/Frameworks/Python.framework/Versions/3.13/bin/python3.13-intel64" \
               "$APP/Contents/Frameworks/Python.framework/Versions/3.13/Resources/Python.app/Contents/MacOS/Python"; do
        [ -f "$bin" ] && codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$bin"
    done
    # Dylib
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" \
        "$APP/Contents/Frameworks/Python.framework/Versions/3.13/Python"
    # Framework bundle
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" \
        "$APP/Contents/Frameworks/Python.framework"
fi

# App bundle
codesign --force --options runtime \
  --sign "$SIGNING_IDENTITY" \
  --entitlements "Govorun/Govorun.entitlements" \
  "$APP"

# 4. Проверка подписи
echo "==> Проверка подписи..."
codesign --verify --deep --strict "$APP"
spctl --assess --type execute "$APP" || echo "WARN: spctl проверка не прошла (ожидаемо до notarize)"

# 5. Create DMG
echo "==> Создание DMG..."
hdiutil create -volname "$APP_NAME" \
  -srcfolder "$APP" \
  -ov -format UDZO \
  "$DMG"

# 6. Sign DMG
echo "==> Подпись DMG..."
codesign --sign "$SIGNING_IDENTITY" "$DMG"

# 7. Notarize
echo "==> Нотаризация (может занять несколько минут)..."
xcrun notarytool submit "$DMG" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

# 8. Staple
echo "==> Staple..."
xcrun stapler staple "$DMG"

# 9. Финальная проверка подписи и нотаризации
echo "==> Финальная проверка..."
codesign --verify --deep --strict "$APP" || { echo "ERROR: codesign verification failed" >&2; exit 1; }
spctl --assess --type open --context context:primary-signature "$DMG" || { echo "ERROR: spctl assessment failed — DMG may not be properly notarized" >&2; exit 1; }

echo ""
echo "==> $DMG готов к распространению"
echo "    Размер: $(du -h "$DMG" | cut -f1)"
