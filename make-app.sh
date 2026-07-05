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

# --- Sparkle: embute o framework no bundle -----------------------------------
# O binário linka Sparkle.framework, então ele PRECISA estar em Contents/Frameworks
# pra o app sequer abrir. Localiza o framework buildado pelo SwiftPM.
FRAMEWORKS="$APP/Contents/Frameworks"
SPARKLE_FW="$(find .build -type d -name 'Sparkle.framework' 2>/dev/null | head -1)"
if [ -n "$SPARKLE_FW" ]; then
    echo "==> Embutindo Sparkle.framework…"
    mkdir -p "$FRAMEWORKS"
    cp -R "$SPARKLE_FW" "$FRAMEWORKS/"
    # rpath pro loader achar o framework a partir do executável
    install_name_tool -add_rpath "@executable_path/../Frameworks" \
        "$APP/Contents/MacOS/Harbofly" 2>/dev/null || true
else
    echo "AVISO: Sparkle.framework não encontrado em .build (rode 'swift build' antes)."
fi

# --- Sparkle: chaves no Info.plist -------------------------------------------
# Só injeta as chaves de update se SU_PUBLIC_ED_KEY estiver setado. Sem a chave,
# o app roda com o framework embutido porém INERTE (nenhuma checagem de rede) —
# mantém a base de privacidade até você configurar a distribuição.
SU_FEED_URL="${SU_FEED_URL:-https://raw.githubusercontent.com/carloshpdoc/Harbofly/main/appcast.xml}"
SU_KEYS=""
if [ -n "${SU_PUBLIC_ED_KEY:-}" ]; then
    echo "==> Update via Sparkle habilitado (feed: ${SU_FEED_URL})"
    SU_KEYS="    <key>SUFeedURL</key><string>${SU_FEED_URL}</string>
    <key>SUPublicEDKey</key><string>${SU_PUBLIC_ED_KEY}</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUScheduledCheckInterval</key><integer>28800</integer>"
else
    echo "AVISO: SU_PUBLIC_ED_KEY não setado — Sparkle fica inerte (sem auto-update)."
fi

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
${SU_KEYS}
</dict>
</plist>
PLIST

# SIGN_ID:
#   "-"  (default)  → assinatura ad-hoc (dev local)
#   "Developer ID Application: … (TEAMID)" → assinatura real p/ notarização
SIGN_ID="${SIGN_ID:--}"

# Assina um caminho respeitando o modo (ad-hoc x Developer ID + hardened runtime).
sign_one() {
    if [ "$SIGN_ID" = "-" ]; then
        codesign --force --sign - "$1"
    else
        codesign --force --timestamp --options runtime --sign "$SIGN_ID" "$1"
    fi
}

# Sparkle exige assinatura INSIDE-OUT (componentes internos antes do framework,
# framework antes do app). '--deep' quebra a notarização do Sparkle.
FW="$FRAMEWORKS/Sparkle.framework"
if [ -d "$FW" ]; then
    echo "==> Assinando componentes do Sparkle (inside-out)…"
    # XPC services e helpers aninhados primeiro
    while IFS= read -r -d '' c; do sign_one "$c"; done \
        < <(find "$FW" -type d \( -name '*.xpc' -o -name '*.app' \) -print0)
    [ -f "$FW/Versions/Current/Autoupdate" ] && sign_one "$FW/Versions/Current/Autoupdate"
    sign_one "$FW"
fi

echo "==> Assinando ${APP} ($([ "$SIGN_ID" = "-" ] && echo ad-hoc || echo Developer ID + hardened runtime))…"
sign_one "$APP"
if [ "$SIGN_ID" != "-" ]; then
    codesign --verify --strict --verbose=2 "$APP"
fi

echo "==> Pronto: $(pwd)/$APP"
echo "    Abrir com: open $APP"
