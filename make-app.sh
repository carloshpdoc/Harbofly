#!/bin/bash
# Monta DiskWatch.app a partir do binário SwiftPM (release).
set -euo pipefail
cd "$(dirname "$0")"

APP="DiskWatch.app"
BIN=".build/release/DiskWatch"

echo "==> Compilando (release)…"
xcrun swift build -c release

echo "==> Montando ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DiskWatch"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DiskWatch</string>
    <key>CFBundleDisplayName</key><string>DiskWatch</string>
    <key>CFBundleIdentifier</key><string>com.carloscarmo.diskwatch</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>DiskWatch</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> Assinando (ad-hoc)…"
codesign --force --deep --sign - "$APP"

echo "==> Pronto: $(pwd)/$APP"
echo "    Abrir com: open $APP"
