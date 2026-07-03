#!/bin/bash
# Gera Harbofly.dmg assinado + notarizado + stapled (distribuicao publica).
# Layout arrasta-pra-Applications, sem dependencias (hdiutil puro).
#
# Notariza DUAS vezes (o .app e depois o .dmg) pra o app funcionar mesmo offline
# no primeiro launch (ticket stapled no app e no dmg).
#
# Requer env: SIGN_ID, ASC_KEY_ID, ASC_ISSUER_ID  (ver ~/.zshrc)
set -euo pipefail
cd "$(dirname "$0")"

APP="Harbofly.app"
DMG="Harbofly.dmg"
VOL="Harbofly"
ZIP_TMP="Harbofly-notarize-app.zip"

: "${ASC_KEY_ID:?Set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
: "${SIGN_ID:?Set SIGN_ID (Developer ID Application: <Nome> (<TeamID>))}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
[ -f "$ASC_KEY_PATH" ] || { echo "ERRO: API key nao encontrada: $ASC_KEY_PATH"; exit 1; }
export SIGN_ID

notarize() {  # $1 = arquivo a submeter
    xcrun notarytool submit "$1" \
        --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
}

# 1) Build + assinatura Developer ID (herdando SIGN_ID)
./make-app.sh

# 2) Notariza + staple o .app
echo "==> Notarizando o app…"
rm -f "$ZIP_TMP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP_TMP"
notarize "$ZIP_TMP"
xcrun stapler staple "$APP"
rm -f "$ZIP_TMP"

# 3) Monta o .dmg estilizado (create-dmg: janela + icone do app + seta pro Applications)
command -v create-dmg >/dev/null || { echo "ERRO: create-dmg nao instalado (brew install create-dmg)"; exit 1; }
echo "==> Montando ${DMG} (create-dmg)…"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
rm -f "$DMG"
# create-dmg pode retornar !=0 mesmo produzindo o dmg; validamos pela existencia do arquivo.
set +e
create-dmg \
    --volname "$VOL" \
    --volicon "Assets/Harbofly.icns" \
    --window-pos 200 120 \
    --window-size 540 380 \
    --icon-size 128 \
    --icon "$APP" 140 190 \
    --hide-extension "$APP" \
    --app-drop-link 400 190 \
    "$DMG" "$STAGE"
set -e
rm -rf "$STAGE"
[ -f "$DMG" ] || { echo "ERRO: create-dmg nao gerou $DMG"; exit 1; }

# 4) Assina + notariza + staple o .dmg
echo "==> Assinando e notarizando o ${DMG}…"
codesign --force --sign "$SIGN_ID" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Verificacao Gatekeeper (dmg):"
spctl -a -vvv -t open --context context:primary-signature "$DMG" || true

echo "==> Pronto! Distribua: $(pwd)/$DMG"
