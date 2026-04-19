#!/bin/bash
# build.sh — compile WinExplorer, bundle icon, sign, and create DMGs
set -e
cd "$(dirname "$0")"

ARCH="${1:-$(uname -m)}"   # default to host arch; pass arm64 or x86_64 to override
SRC="WinExplorer"
APP="WinExplorer.app"
BUNDLE="$APP/Contents"
SOURCES=(
    "$SRC/main.swift"
    "$SRC/FileManagerViewModel.swift"
    "$SRC/ContentView.swift"
    "$SRC/FileItem.swift"
    "$SRC/AddressBarView.swift"
    "$SRC/FileGridView.swift"
    "$SRC/FileListView.swift"
    "$SRC/SidebarView.swift"
    "$SRC/StatusBarView.swift"
    "$SRC/WinExplorerApp.swift"
)

echo "▶ Compiling for $ARCH..."
swiftc -target "$ARCH-apple-macos13.0" -O "${SOURCES[@]}" \
    -framework SwiftUI -framework AppKit \
    -o "$BUNDLE/MacOS/WinExplorer"

echo "▶ Bundling icon..."
mkdir -p "$BUNDLE/Resources"
# Copy PNG for runtime loading
cp "$SRC/AppIcon.png" "$BUNDLE/MacOS/AppIcon.png"
# Build multi-resolution icns for Dock/Finder
ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
    sips -z $SIZE $SIZE "$SRC/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png"       2>/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z $DOUBLE $DOUBLE "$SRC/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" 2>/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUNDLE/Resources/AppIcon.icns"

echo "▶ Signing..."
codesign --force --deep --sign - "$APP"

echo "▶ Building DMG..."
SUFFIX=$([ "$ARCH" = "arm64" ] && echo "AppleSilicon" || echo "Intel")
DMG="WinExplorer-1.0-${SUFFIX}.dmg"
rm -f "$DMG"
STAGING=$(mktemp -d)
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "WinExplorer" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "✅ Done: $DMG"
