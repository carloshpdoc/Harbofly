# Poof ☁️

> Disco lotado? **Poof.** Sumiu.

App de menu bar para macOS que **descobre sozinho** o que está ocupando seu disco e deixa você limpar com um clique — sem configurar path nenhum.

Nasceu de uma dor real: um Mac de dev iOS/Android acumula dezenas de GB em build artifacts e caches (`build/`, `.build/`, `node_modules/`, `DerivedData`, caches de SPM/Homebrew/Yarn/pip…) que ninguém lembra de limpar. O Poof varre esses lugares automaticamente, mostra quanto dá pra recuperar e organiza por nível de risco.

## Features

- **Auto-discovery** — varre `~/Development` procurando `build`, `.build`, `node_modules`, `Pods`, `DerivedData` e os caches conhecidos de `~/Library`. Zero config de path.
- **Barra de disco** no topo com cor por pressão: verde → laranja (<20%) → **vermelho (<10%)**.
- **"Recuperável: X GB"** — soma do que dá pra limpar agora.
- **Tiers de risco:**
  - 🟢 **Seguro** — regenera sozinho no próximo build.
  - 🟡 **Cuidado** — recria, mas custa (recompilar do zero, re-baixar símbolos de device).
- **Cada item mostra** nome, caminho completo e o que é.
- **"Selecionar seguros"** marca o tier seguro inteiro de uma vez.
- **Exclusão permanente** com confirmação — libera o espaço na hora (não vai pra Lixeira, porque no mesmo volume a Lixeira não libera espaço até ser esvaziada).
- **Rescan automático** a cada 30 min + botão manual.

## O que ele varre

**`~/Development`** (auto-discovery, profundidade até 3):
`build`, `.build`, `node_modules`, `Pods`, `DerivedData` — tudo classificado como 🟢 Seguro.

**`~/Library`** (alvos conhecidos):

| Path | Tier | O que é |
|------|------|---------|
| `Developer/Xcode/DerivedData` | 🟢 | Intermediários de build do Xcode |
| `Developer/XcodeBuildMCP/workspaces` | 🟢 | Workspaces do XcodeBuildMCP |
| `Caches/org.swift.swiftpm` | 🟢 | Cache do Swift Package Manager |
| `Caches/Homebrew` | 🟢 | Downloads do Homebrew |
| `Caches/Yarn` | 🟢 | Cache do Yarn |
| `Caches/pip` | 🟢 | Cache do pip |
| `Developer/Xcode/iOS DeviceSupport` | 🟡 | Símbolos de devices (recria ao conectar iPhone) |
| `Caches/ms-playwright` | 🟡 | Browsers baixados pelo Playwright |
| `Caches/Google` | 🟡 | Cache do Google/Chrome |

Itens abaixo de 10 MB são ignorados pra reduzir ruído. Os alvos ficam em `scanDevelopment()` e `scanLibrary()` no `Sources/DiskWatch/App.swift` — fáceis de ajustar.

## Requisitos

- macOS 14+
- Swift 6 (toolchain do Xcode)

## Build & Run

```bash
# Gera Poof.app assinado (ad-hoc) e mostra onde ficou
./make-app.sh

# Abre o app (ícone aparece na barra de menu)
open Poof.app
```

Para distribuir fora da Mac App Store (assina com Developer ID, notariza e "staple"):

```bash
# requer ASC_KEY_ID e ASC_ISSUER_ID no ambiente + a .p8 em ~/.appstoreconnect/private_keys/
./notarize.sh   # produz Poof.zip pronto pra download
```

Durante o desenvolvimento:

```bash
xcrun swift build            # debug
xcrun swift run              # roda direto (sem .app)
xcrun swift build -c release # release
```

## Estrutura

```
DiskWatch/                       # pasta/target interno do SwiftPM
├── Package.swift                # SwiftPM (macOS 14+)
├── Sources/DiskWatch/App.swift  # app inteiro: scanner + UI (nome de exibição em AppInfo.name)
├── make-app.sh                  # monta o Poof.app
├── notarize.sh                  # assina (Developer ID) + notariza + staple
└── README.md
```

## Roadmap

- [x] Launch no login (`SMAppService`)
- [x] Notarização (Developer ID, fora da MAS)
- [ ] Tier 3 informativo (CoreSimulator, Application Support, Downloads) — só leitura
- [ ] Default para Lixeira (permanente como opção)
- [ ] Notificação quando o disco cair abaixo de X%
- [ ] Ícone próprio
