#!/bin/bash
# Assina (Developer ID), notariza e "staple" o Poof.app.
# Produz um .zip pronto pra distribuir fora da Mac App Store.
#
# Credenciais via env (ex.: exportadas no ~/.zshrc — NUNCA commitar no repo):
#   ASC_KEY_ID     App Store Connect API Key ID          (obrigatório)
#   ASC_ISSUER_ID  App Store Connect API Issuer ID (UUID)(obrigatório)
#   ASC_KEY_PATH   Caminho do .p8                        (default: ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8)
#   SIGN_ID        Identidade Developer ID Application   (default: Carlos … REDACTED)
set -euo pipefail
cd "$(dirname "$0")"

APP="Poof.app"
ZIP="Poof.zip"

# Credenciais NÃO ficam no repo — leia do ambiente (ex.: exportadas no ~/.zshrc).
: "${ASC_KEY_ID:?Set ASC_KEY_ID (App Store Connect API Key ID)}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID (App Store Connect API Issuer ID / UUID)}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
export SIGN_ID="${SIGN_ID:-Developer ID Application: REDACTED (REDACTED)}"

[ -f "$ASC_KEY_PATH" ] || { echo "ERRO: API key não encontrada: $ASC_KEY_PATH"; exit 1; }

# 1) Build + assinatura Developer ID (via make-app.sh, herdando SIGN_ID)
./make-app.sh

# 2) Zip preservando o bundle
echo "==> Zipando ${APP}…"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

# 3) Notarizar (aguarda o resultado)
echo "==> Enviando pra notarização (pode levar alguns minutos)…"
xcrun notarytool submit "$ZIP" \
    --key "$ASC_KEY_PATH" \
    --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" \
    --wait

# 4) Staple no .app e re-zipar pra distribuir
echo "==> Staple…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Re-zipando com o ticket…"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

# 5) Verificação final (o que o Gatekeeper vê)
echo "==> Verificação Gatekeeper:"
spctl -a -vvv -t exec "$APP" || true

echo "==> Pronto! Distribua: $(pwd)/$ZIP"
