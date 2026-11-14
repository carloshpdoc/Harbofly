#!/usr/bin/env bash
# Verificação do modo "Discos".
#
# Monta dois volumes de verdade com `hdiutil` (um exFAT, um APFS) e planta neles
# os casos que a lógica tem de acertar. Volume real em vez de mock porque o que
# se testa aqui é comportamento de volume: flags de montagem, Lixeira por
# volume, slack de cluster do exFAT, AppleDouble que o macOS cria em FS sem
# xattr. Nenhum mock de FileManager exercita isso.
#
# Onde `hdiutil create` é negado (a partir do macOS 26/27 ele exige permissão
# que um shell sem Full Disk Access não tem), o script cai para duas PASTAS e
# segue rodando: os testes de motor — porta de cobertura, baldes, subárvore,
# NFC/NFD, keeper — valem igual. Só os de classificação de volume são pulados,
# e o script diz quais.
#
# Uso:  tools/t/volumes-fixture.sh [caminho-do-binario]
#
# Não toca em nada fora de $WORK (mktemp -d) e dos volumes que ele mesmo monta;
# desmonta tudo na saída, inclusive em erro.

set -uo pipefail

BIN="${1:-.build/debug/Harbofly}"
[[ -x "$BIN" ]] || { echo "binário não encontrado: $BIN" >&2; exit 1; }
BIN="$(cd "$(dirname "$BIN")" && pwd)/$(basename "$BIN")"

# O binário do pacote linka Sparkle por @rpath; fora do .app precisa disto.
FW="$(cd "$(dirname "$BIN")/../out/Products/Debug" 2>/dev/null && pwd || true)"
[[ -n "$FW" ]] && export DYLD_FRAMEWORK_PATH="$FW"

WORK="$(mktemp -d)"
NAME_A="HarboflyFixA"
NAME_B="HarboflyFixB"
MODE="images"
FAILS=0
SKIPS=0

cleanup() {
    chmod -R u+rwX "$WORK" >/dev/null 2>&1
    if [[ "$MODE" == "images" ]]; then
        for v in "/Volumes/$NAME_A" "/Volumes/$NAME_B"; do
            [[ -d "$v" ]] && hdiutil detach "$v" -force >/dev/null 2>&1
        done
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; }
fail() { printf '  \033[31mFALHA\033[0m %s\n' "$1"; FAILS=$((FAILS + 1)); }
skip() { printf '  \033[33m--\033[0m    %s\n' "$1"; SKIPS=$((SKIPS + 1)); }

has()  { printf '%s' "$2" | grep -qE "$1"; }
want() { # want <descrição> <regex> <texto>
    if has "$2" "$3"; then ok "$1"; else
        fail "$1 (esperava /$2/)"
        printf '%s\n' "$3" | sed 's/^/        | /' | head -20
    fi
}
reject() { # reject <descrição> <regex-que-NÃO-pode-aparecer> <texto>
    if has "$2" "$3"; then fail "$1"; else ok "$1"; fi
}

echo "== preparando as duas pontas =="
if hdiutil create -size 220m -fs "ExFAT" -volname "$NAME_A" -quiet "$WORK/a.dmg" 2>/dev/null \
   && hdiutil create -size 220m -fs "APFS" -volname "$NAME_B" -quiet "$WORK/b.dmg" 2>/dev/null \
   && hdiutil attach "$WORK/a.dmg" -quiet 2>/dev/null \
   && hdiutil attach "$WORK/b.dmg" -quiet 2>/dev/null \
   && [[ -d "/Volumes/$NAME_A" && -d "/Volumes/$NAME_B" ]]; then
    A="/Volumes/$NAME_A"; B="/Volumes/$NAME_B"
    echo "  volumes montados: $A (exfat) e $B (apfs)"
else
    MODE="dirs"
    A="$WORK/volA"; B="$WORK/volB"
    mkdir -p "$A" "$B"
    echo "  hdiutil indisponível neste ambiente — usando pastas:"
    echo "    $A e $B"
    echo "  (testes de classificação de volume serão pulados)"
fi

echo
echo "== plantando os casos =="
# 1) par idêntico nas duas pontas (o caso central)
mkdir -p "$A/comum" "$B/comum"
head -c 300000 /dev/urandom > "$WORK/igual.bin"
cp "$WORK/igual.bin" "$A/comum/igual.bin"
cp "$WORK/igual.bin" "$B/comum/igual.bin"

# 2) mesmo nome, conteúdo diferente — NÃO é duplicata
head -c 300000 /dev/urandom > "$A/comum/divergente.bin"
head -c 300000 /dev/urandom > "$B/comum/divergente.bin"

# 3) mesmo TAMANHO, conteúdo diferente: separa a fase 1 (tamanho) da fase 3 (hash)
head -c 123456 /dev/urandom > "$A/mesmo-tamanho-1.bin"
head -c 123456 /dev/urandom > "$A/mesmo-tamanho-2.bin"

# 4) hardlink: mesma cópia física, apagar não libera nada
head -c 200000 /dev/urandom > "$A/hard-original.bin"
ln "$A/hard-original.bin" "$A/hard-link.bin" 2>/dev/null \
    || echo "  (sem hardlink nesta ponta — caso não exercitado)"

# 5) symlink
ln -s "$A/comum/igual.bin" "$A/atalho.bin"

# 6) AppleDouble e .DS_Store. O `._` quase nunca aparece na contagem — o macOS
#    esconde AppleDouble do FileManager — então o que se exige dele é só que
#    nunca chegue à lista de candidatos.
head -c 9000 /dev/urandom > "$A/._fantasma.bin"
head -c 9000 /dev/urandom > "$A/.DS_Store"

# 7) área de serviço do Windows, com conteúdo dentro
mkdir -p "$A/\$RECYCLE.BIN/S-1-5-21"
head -c 400000 /dev/urandom > "$A/\$RECYCLE.BIN/S-1-5-21/apagado.bin"
# a mesma área em outro nível: tem de agregar numa linha, não repetir
mkdir -p "$A/comum/.Spotlight-V100" "$A/.Spotlight-V100"
head -c 20000 /dev/urandom > "$A/comum/.Spotlight-V100/i.bin"
head -c 20000 /dev/urandom > "$A/.Spotlight-V100/i.bin"

# 8) ilegível de duas formas:
#    - arquivo sem permissão de leitura: o `lstat` AINDA funciona (os metadados
#      são do diretório), então ele entra no índice normalmente. O que não pode
#      é ser oferecido como duplicata sem conseguir ler o conteúdo.
#    - pasta sem permissão: aí o enumerador falha de fato, e esse é o erro que a
#      porta de cobertura precisa contar em vez de engolir.
head -c 50000 /dev/urandom > "$A/sem-permissao.bin"
chmod 000 "$A/sem-permissao.bin" 2>/dev/null || true
mkdir -p "$A/pasta-fechada"
head -c 60000 /dev/urandom > "$A/pasta-fechada/escondido.bin"
chmod 000 "$A/pasta-fechada" 2>/dev/null || true

# 9) subárvore inteiramente duplicada (o caso dos node_modules)
mkdir -p "$A/arvore/sub" "$B/arvore/sub"
for i in 1 2 3; do
    head -c 80000 /dev/urandom > "$WORK/t$i.bin"
    cp "$WORK/t$i.bin" "$A/arvore/sub/t$i.bin"
    cp "$WORK/t$i.bin" "$B/arvore/sub/t$i.bin"
done

# 10) acento gravado em NFC e em NFD, mesmo conteúdo
python3 - "$A" "$B" <<'PY'
import sys, unicodedata, os
data = os.urandom(70000)
a, b = sys.argv[1], sys.argv[2]
with open(os.path.join(a, unicodedata.normalize("NFD", "Currículo.doc")), "wb") as f:
    f.write(data)
with open(os.path.join(b, unicodedata.normalize("NFC", "Currículo.doc")), "wb") as f:
    f.write(data)
PY

# 11) ruído abaixo do piso de 4 KB: conta no espaço, fora do índice
for i in $(seq 1 25); do head -c 500 /dev/urandom > "$A/mini-$i.bin"; done

sync

if [[ "$MODE" == "images" ]]; then
    echo
    echo "== harbofly volumes =="
    OUT="$("$BIN" volumes 2>&1)"
    want   "o volume exFAT de teste aparece"        "$NAME_A"            "$OUT"
    want   "o volume APFS de teste aparece"         "$NAME_B"            "$OUT"
    want   "o exFAT é reconhecido pelo filesystem"  "exfat"              "$OUT"
    reject "partições de sistema ficam de fora"     "/System/Volumes/"   "$OUT"
    reject "/Volumes/Recovery fica de fora"         "/Volumes/Recovery"  "$OUT"
    reject "runtime do CoreSimulator fica de fora"  "CoreSimulator"      "$OUT"
else
    echo
    echo "== harbofly volumes (pulado: exige volumes montados) =="
    skip "classificação de volume (flags, Lixeira, filtro de sistema)"
    # O que dá para afirmar sem montar nada: a lista real deste Mac não traz
    # partição de sistema nem DMG montado.
    OUT="$("$BIN" volumes 2>&1)"
    reject "partições de sistema ficam de fora dos volumes reais" "/System/Volumes/" "$OUT"
    reject "/Volumes/Recovery fica de fora dos volumes reais"     "/Volumes/Recovery" "$OUT"
fi

echo
echo "== harbofly index: a porta de cobertura =="
OUT="$("$BIN" index "$A" 2>/dev/null)"
want "a cobertura fecha"                       "coverage: .* OK"  "$OUT"
want "a pasta sem permissão entrou como erro"  "errors:"          "$OUT"
want "o symlink entrou como descarte"          "symlink"          "$OUT"
want "o ruído abaixo do piso entrou"           "tooSmall"         "$OUT"
want "a área de serviço aparece com tamanho"   'RECYCLE.BIN'      "$OUT"
# agregação: .Spotlight-V100 foi plantado em dois níveis e deve virar UMA linha
SPOT=$(printf '%s' "$OUT" | grep -c "Spotlight-V100")
if [[ "$SPOT" -eq 1 ]]; then
    ok "áreas de serviço repetidas foram agregadas numa linha"
else
    fail "Spotlight-V100 apareceu em $SPOT linha(s), esperava 1"
fi

"$BIN" index "$A" --json 2>/dev/null > "$WORK/idx.json"
python3 - "$WORK/idx.json" <<'PY' || exit 9
import json, sys
d = json.load(open(sys.argv[1]))
ind, enu = d["indexed"], d["enumerated"]
sk, er = sum(d["skipped"].values()), sum(d["errors"].values())
bad = []
if ind + sk + er != enu or not d["coverageOK"]:
    bad.append("a conta não fecha: %d + %d + %d != %d" % (ind, sk, er, enu))
if er < 1:
    bad.append("a pasta sem permissão não foi contada como erro")
if d["bytesAllocated"] < d["bytesLogical"]:
    bad.append("alocado menor que lógico")
for m in bad:
    print("  \033[31mFALHA\033[0m " + m)
if bad:
    sys.exit(1)
print("  \033[32mok\033[0m    JSON fecha: %d + %d + %d = %d" % (ind, sk, er, enu))
print("  \033[32mok\033[0m    erros contados: %s" % d["errors"])
PY
[[ $? -eq 0 ]] || FAILS=$((FAILS + 1))

echo
echo "== harbofly compare: os baldes =="
OUT="$("$BIN" compare "$A" "$B" --subtrees 2>/dev/null)"
want   "a comparação resume os três baldes"   "already elsewhere" "$OUT"
want   "o balde 'só aqui' existe"             "only here"           "$OUT"
want   "a cobertura das duas pontas fecha"    "coverage: OK"        "$OUT"
want   "a subárvore duplicada foi detectada"  "arvore"              "$OUT"
want   "nada foi apagado sem --apply"         "dry-run"             "$OUT"
reject "nenhuma divergência hash-vs-bytes"    "VERIFY MISMATCHES"   "$OUT"

"$BIN" compare "$A" "$B" --json 2>/dev/null > "$WORK/cmp.json"
python3 - "$WORK/cmp.json" "$A" <<'PY' || exit 9
import json, sys
d = json.load(open(sys.argv[1]))
target = sys.argv[2].rstrip("/") + "/"
paths = [r["path"] for r in d["shared"]]
bad = []
if not any("igual.bin" in p for p in paths):
    bad.append("o par idêntico não entrou em 'shared'")
if any("divergente" in p for p in paths):
    bad.append("arquivo de conteúdo diferente entrou como duplicata")
if any("mesmo-tamanho" in p for p in paths):
    bad.append("mesmo tamanho com conteúdo diferente virou duplicata")
if any("hard-" in p for p in paths):
    bad.append("hardlink foi oferecido como duplicata (não libera espaço)")
if any("atalho" in p for p in paths):
    bad.append("symlink entrou na lista")
if any("._" in p.split("/")[-1] for p in paths):
    bad.append("AppleDouble entrou na lista")
if any("RECYCLE" in p for p in paths):
    bad.append("conteúdo de área de serviço entrou na lista")
if not any("Curr" in p for p in paths):
    bad.append("o par NFC/NFD não foi reconhecido como idêntico")
# Conteúdo que não se consegue ler não pode ser oferecido como duplicata; o
# lugar dele é "só aqui", que nunca é apagado.
if any("sem-permissao" in p for p in paths):
    bad.append("arquivo ilegível foi oferecido como duplicata")
if d["verifyMismatches"] != 0:
    bad.append("verifyMismatches != 0")
if not d["coverageOK"]:
    bad.append("coverageOK falso")
for r in d["shared"]:
    if r["keeper"].startswith(target):
        bad.append("o keeper ficou no alvo: " + r["keeper"]); break
if not any("arvore" in s["path"] for s in d["subtrees"]):
    bad.append("a subárvore duplicada não foi reportada")
for m in bad:
    print("  \033[31mFALHA\033[0m " + m)
if bad:
    sys.exit(1)
print("  \033[32mok\033[0m    %d linha(s) em 'shared', keeper sempre fora do alvo" % len(paths))
print("  \033[32mok\033[0m    hardlink, symlink, AppleDouble e área de serviço ficaram fora")
print("  \033[32mok\033[0m    par NFC/NFD reconhecido como o mesmo conteúdo")
print("  \033[32mok\033[0m    só-aqui: %d arquivo(s), %d subárvore(s) duplicada(s)"
      % (d["uniqueFiles"], len(d["subtrees"])))
PY
[[ $? -eq 0 ]] || FAILS=$((FAILS + 1))

echo
echo "== --apply respeita o que foi provado =="
chmod 755 "$A/pasta-fechada" 2>/dev/null || true   # para o find conseguir contar
BEFORE=$(find "$A" -type f 2>/dev/null | wc -l | tr -d ' ')
OUT="$("$BIN" compare "$A" "$B" --apply --permanent 2>/dev/null)"
AFTER=$(find "$A" -type f 2>/dev/null | wc -l | tr -d ' ')
want "relatou o que removeu" "Deleted|freed" "$OUT"
if [[ "$AFTER" -lt "$BEFORE" ]]; then
    ok "arquivos provados idênticos saíram do alvo ($BEFORE → $AFTER)"
else
    fail "nada saiu do alvo ($BEFORE → $AFTER)"
fi
for keep in "comum/divergente.bin" "mesmo-tamanho-1.bin" "mesmo-tamanho-2.bin"; do
    if [[ -f "$A/$keep" ]]; then ok "preservado: $keep"; else fail "APAGOU indevidamente: $keep"; fi
done
if [[ -f "$B/comum/igual.bin" ]]; then
    ok "a cópia do outro lado (o keeper) continua lá"
else
    fail "o keeper foi apagado do outro lado"
fi
if [[ -f "$A/\$RECYCLE.BIN/S-1-5-21/apagado.bin" ]]; then
    ok "a área de serviço não foi tocada"
else
    fail "conteúdo de área de serviço foi apagado"
fi

if [[ "$MODE" == "images" ]]; then
    echo
    echo "== volume só-leitura recusa escrita =="
    hdiutil detach "$B" -force >/dev/null 2>&1
    hdiutil attach "$WORK/b.dmg" -readonly -quiet 2>/dev/null
    if [[ -d "$B" ]]; then
        want   "aparece em --all como só-leitura"   "read-only" "$("$BIN" volumes --all 2>&1)"
        reject "fica fora da lista normal"          "$NAME_B"   "$("$BIN" volumes 2>&1)"
    fi
    echo
    echo "== volume ejetado no meio do caminho =="
    hdiutil detach "$A" -force >/dev/null 2>&1
    OUT="$("$BIN" index "$A" 2>&1)"
    want "não travou nem estourou" "No such path|coverage" "$OUT"
else
    echo
    skip "volume só-leitura e ejeção (exigem volumes montados)"
fi

echo
if [[ $FAILS -eq 0 ]]; then
    printf '\033[32mtudo passou\033[0m'
    [[ $SKIPS -gt 0 ]] && printf ' (%d bloco(s) pulado(s) por falta de hdiutil)' "$SKIPS"
    printf '\n'
else
    printf '\033[31m%d verificação(ões) falharam\033[0m\n' "$FAILS"
fi
exit $((FAILS > 0 ? 1 : 0))
