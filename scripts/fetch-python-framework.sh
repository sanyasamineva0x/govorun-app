#!/bin/bash
set -euo pipefail

# Скачать и подготовить Python.framework для встраивания в Govorun.app
# Запускать один раз после клонирования репозитория

PYTHON_VERSION="3.13.12"
PKG_URL="https://www.python.org/ftp/python/${PYTHON_VERSION}/python-${PYTHON_VERSION}-macos11.pkg"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FRAMEWORK_DIR="$PROJECT_DIR/Frameworks/Python.framework"

if [ -d "$FRAMEWORK_DIR" ]; then
    echo "Python.framework уже существует в $FRAMEWORK_DIR"
    "$FRAMEWORK_DIR/Versions/3.13/bin/python3" --version 2>/dev/null || echo "WARN: framework повреждён"
    exit 0
fi

echo "==> Скачиваю Python ${PYTHON_VERSION} macOS universal2..."
TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

curl -L -o "$TMPDIR/python.pkg" "$PKG_URL"

echo "==> Извлекаю Python.framework..."
pkgutil --expand "$TMPDIR/python.pkg" "$TMPDIR/expanded"

cd "$TMPDIR"
mkdir -p framework
cd framework
cat "$TMPDIR/expanded/Python_Framework.pkg/Payload" | gunzip -c | cpio -id 2>/dev/null

# Восстановить Python.app (нужен для запуска python3)
cd "$TMPDIR"
cat "$TMPDIR/expanded/Python_Framework.pkg/Payload" | gunzip -c | cpio -id "*/Resources/Python.app/*" 2>/dev/null
if [ -d "$TMPDIR/Versions/3.13/Resources/Python.app" ]; then
    cp -R "$TMPDIR/Versions/3.13/Resources/Python.app" "$TMPDIR/framework/Versions/3.13/Resources/"
fi

PYFW="$TMPDIR/framework/Versions/3.13"

echo "==> Удаляю ненужное (test, Tk/Tcl, share, idlelib)..."
rm -rf "$PYFW/lib/python3.13/test"
rm -rf "$PYFW/Frameworks"
rm -rf "$PYFW/share"
rm -rf "$PYFW/lib/python3.13/idlelib"
rm -rf "$PYFW/lib/python3.13/tkinter"
rm -rf "$PYFW/lib/python3.13/turtle"*
rm -rf "$PYFW/lib/python3.13/turtledemo"
rm -rf "$PYFW/lib/python3.13/__phello__"
rm -f "$PYFW/lib/python3.13/lib-dynload/_tkinter"*.so
find "$PYFW/lib/python3.13" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

echo "==> Исправляю install names для embedded использования..."
OLD_ID="/Library/Frameworks/Python.framework/Versions/3.13/Python"

# Dylib identity
install_name_tool -id "@rpath/Python.framework/Versions/3.13/Python" "$PYFW/Python" 2>/dev/null || true

# python3.13 binary
install_name_tool -change "$OLD_ID" "@loader_path/../Python" "$PYFW/bin/python3.13" 2>/dev/null || true

# python3.13-intel64 (Rosetta)
[ -f "$PYFW/bin/python3.13-intel64" ] && \
    install_name_tool -change "$OLD_ID" "@loader_path/../Python" "$PYFW/bin/python3.13-intel64" 2>/dev/null || true

# Python.app binary
[ -f "$PYFW/Resources/Python.app/Contents/MacOS/Python" ] && \
    install_name_tool -change "$OLD_ID" "@loader_path/../../../../Python" "$PYFW/Resources/Python.app/Contents/MacOS/Python" 2>/dev/null || true

# .so files in lib-dynload
for f in "$PYFW"/lib/python3.13/lib-dynload/*.so; do
    [ -f "$f" ] || continue
    install_name_tool -change "$OLD_ID" "@loader_path/../../../Python" "$f" 2>/dev/null || true
done

# Bundled dylibs (ssl, crypto, ncurses, etc.)
for f in "$PYFW"/lib/*.dylib; do
    [ -f "$f" ] || continue
    basename=$(basename "$f")
    # Fix self-identity
    install_name_tool -id "@rpath/Python.framework/Versions/3.13/lib/$basename" "$f" 2>/dev/null || true
    # Fix reference to Python dylib
    install_name_tool -change "$OLD_ID" "@loader_path/../Python" "$f" 2>/dev/null || true
done

# Cross-references between bundled dylibs
for f in "$PYFW"/lib/libform.6.dylib "$PYFW"/lib/libpanel.6.dylib "$PYFW"/lib/libmenu.6.dylib; do
    [ -f "$f" ] || continue
    install_name_tool -change "/Library/Frameworks/Python.framework/Versions/3.13/lib/libncurses.6.dylib" \
        "@loader_path/libncurses.6.dylib" "$f" 2>/dev/null || true
done
[ -f "$PYFW/lib/libssl.3.dylib" ] && \
    install_name_tool -change "/Library/Frameworks/Python.framework/Versions/3.13/lib/libcrypto.3.dylib" \
        "@loader_path/libcrypto.3.dylib" "$PYFW/lib/libssl.3.dylib" 2>/dev/null || true

# SSL/crypto references in .so modules
for f in "$PYFW"/lib/python3.13/lib-dynload/_ssl*.so "$PYFW"/lib/python3.13/lib-dynload/_hashlib*.so; do
    [ -f "$f" ] || continue
    for lib in libssl.3.dylib libcrypto.3.dylib; do
        install_name_tool -change "/Library/Frameworks/Python.framework/Versions/3.13/lib/$lib" \
            "@loader_path/../../../lib/$lib" "$f" 2>/dev/null || true
    done
done

# Curses references
for f in "$PYFW"/lib/python3.13/lib-dynload/_curses*.so; do
    [ -f "$f" ] || continue
    for lib in libncurses.6.dylib libpanel.6.dylib libmenu.6.dylib libform.6.dylib; do
        install_name_tool -change "/Library/Frameworks/Python.framework/Versions/3.13/lib/$lib" \
            "@loader_path/../../../lib/$lib" "$f" 2>/dev/null || true
    done
done

echo "==> Ad-hoc подпись..."
find "$PYFW" -type f \( -name "*.so" -o -name "*.dylib" \) -exec codesign --force -s - {} \; 2>/dev/null
[ -f "$PYFW/Resources/Python.app/Contents/MacOS/Python" ] && codesign --force -s - "$PYFW/Resources/Python.app/Contents/MacOS/Python" 2>/dev/null
codesign --force -s - "$PYFW/Python" 2>/dev/null
codesign --force -s - "$PYFW/bin/python3.13" 2>/dev/null
[ -f "$PYFW/bin/python3.13-intel64" ] && codesign --force -s - "$PYFW/bin/python3.13-intel64" 2>/dev/null

echo "==> Проверка..."
"$PYFW/bin/python3" --version

echo "==> Копирую в $FRAMEWORK_DIR..."
mkdir -p "$PROJECT_DIR/Frameworks"
cp -R "$TMPDIR/framework" "$FRAMEWORK_DIR"

SIZE=$(du -sh "$FRAMEWORK_DIR" | cut -f1)
echo ""
echo "==> Python.framework готов ($SIZE)"
echo "    $FRAMEWORK_DIR/Versions/3.13/bin/python3"
