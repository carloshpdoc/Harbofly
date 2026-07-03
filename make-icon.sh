#!/bin/bash
# Gera AppIcon.icns a partir da arte-mestre Assets/HarboflyIcon.png (1024x1024, alpha).
set -euo pipefail
cd "$(dirname "$0")"

MASTER="Assets/HarboflyIcon.png"
OUT="Assets/Harbofly.icns"
ICONSET="${TMPDIR:-/tmp}/Harbofly-AppIcon.iconset"

if [ ! -f "${MASTER}" ]; then
    echo "Falta ${MASTER} (1024x1024)"
    exit 1
fi

echo "==> Montando .iconset a partir de ${MASTER}"
mkdir -p "${ICONSET}"
for s in 16 32 128 256 512; do
    s2=$((s * 2))
    sips -z "${s}"  "${s}"  "${MASTER}" --out "${ICONSET}/icon_${s}x${s}.png"    >/dev/null
    sips -z "${s2}" "${s2}" "${MASTER}" --out "${ICONSET}/icon_${s}x${s}@2x.png" >/dev/null
done

echo "==> Gerando ${OUT}"
iconutil -c icns "${ICONSET}" -o "${OUT}"
echo "==> Pronto: $(pwd)/${OUT}"
