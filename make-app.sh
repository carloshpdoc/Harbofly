#!/bin/bash
# Monta o .app a partir do binário SwiftPM (release).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Harbofly"                   # nome de exibição / bundle
APP="${APP_NAME}.app"
BIN=".build/release/Harbofly"         # executável do SwiftPM target (interno)
ICON="Assets/Harbofly.icns"

# Versão: SemVer user-facing vem do arquivo VERSION (fonte única);
# build number monotônico = nº de commits (garante que sempre cresce).
VERSION="$(cat VERSION 2>/dev/null || echo 0.0.0)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
echo "==> Versão ${VERSION} (build ${BUILD})"

echo "==> Compilando (release)…"
xcrun swift build -c release

echo "==> Montando ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Harbofly"

cp "$ICON" "$APP/Contents/Resources/Harbofly.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>app.harbofly</string>
    <key>CFBundleVersion</key><string>${BUILD}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>Harbofly</string>
    <key>CFBundleIconFile</key><string>Harbofly.icns</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# SIGN_ID:
#   "-"  (default)  → assinatura ad-hoc (dev local)
#   "Developer ID Application: … (TEAMID)" → assinatura real p/ notarização
SIGN_ID="${SIGN_ID:--}"

if [ "$SIGN_ID" = "-" ]; then
    echo "==> Assinando (ad-hoc)…"
    codesign --force --deep --sign - "$APP"
else
    echo "==> Assinando com Developer ID + hardened runtime…"
    codesign --force --deep --timestamp --options runtime \
        --sign "$SIGN_ID" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
fi

echo "==> Pronto: $(pwd)/$APP"
echo "    Abrir com: open $APP"
