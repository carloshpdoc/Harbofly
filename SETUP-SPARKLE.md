# Setup do auto-update (Sparkle)

O app já está com o Sparkle **embutido e fiado** (menu "Buscar agora", toggle de
auto-update). Ele fica **inerte** até você configurar as chaves abaixo — sem chave,
o app não faz nenhuma checagem de rede.

O que falta é só o que **você** precisa fazer (a chave privada é segredo, não passa
por mim):

## 1. Gerar o par de chaves EdDSA (uma vez)

```bash
# baixa as tools do Sparkle (mesma versão do app)
curl -fsSL https://github.com/sparkle-project/Sparkle/releases/download/2.9.4/Sparkle-2.9.4.tar.xz -o /tmp/sparkle.tar.xz
mkdir -p /tmp/sparkle-tools && tar xJf /tmp/sparkle.tar.xz -C /tmp/sparkle-tools

# gera as chaves: guarda a PRIVADA no seu Keychain e imprime a PÚBLICA
/tmp/sparkle-tools/bin/generate_keys
```

O comando imprime a **chave pública** (algo tipo `SUPublicEDKey: xxxxxx...`).

Pra o CI, exporte a **privada** num arquivo (é o conteúdo que vira o secret):

```bash
/tmp/sparkle-tools/bin/generate_keys -x /tmp/sparkle_private_key
cat /tmp/sparkle_private_key   # copie tudo
```

## 2. Adicionar os secrets no GitHub (repo Harbofly → Settings → Secrets → Actions)

| Secret | Valor |
|---|---|
| `SU_PUBLIC_ED_KEY` | a chave **pública** impressa no passo 1 |
| `SPARKLE_PRIVATE_KEY` | o conteúdo do arquivo `sparkle_private_key` (privada) |

> `SU_PUBLIC_ED_KEY` também pode ir hardcoded no `make-app.sh` (é pública, seguro
> commitar). Se quiser buildar/testar o auto-update localmente:
> `SU_PUBLIC_ED_KEY="sua_chave_publica" ./make-dmg.sh`

## 3. Publicar a próxima versão

```bash
# bump da versão + tag
echo "1.1.0" > VERSION
git commit -am "release: 1.1.0"
git tag v1.1.0 && git push origin main v1.1.0
```

O workflow de release então:
1. builda o app **com** o Sparkle ativo (injeta `SU_PUBLIC_ED_KEY` no Info.plist),
2. notariza + monta o DMG,
3. assina o DMG com a chave EdDSA e **gera o `appcast.xml`** apontando pro asset da Release,
4. commita o `appcast.xml` de volta na `main`.

O app instalado lê `https://raw.githubusercontent.com/carloshpdoc/Harbofly/main/appcast.xml`
e passa a oferecer o update. Usuários do Homebrew continuam atualizando via `brew upgrade`.

## Como validar (primeiro release com Sparkle)

- Instale a v1.0.0 atual, depois publique a v1.1.0.
- Abra o app → "Buscar agora" no rodapé → deve oferecer a 1.1.0.
- Se der "não foi possível verificar a assinatura", confira que `SU_PUBLIC_ED_KEY`
  (no app) e `SPARKLE_PRIVATE_KEY` (no appcast) são o mesmo par.
