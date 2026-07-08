# Harbofly

[![Featured on Awesome Mac](https://awesome.re/mentioned-badge.svg)](https://github.com/jaywcjlove/awesome-mac)

[🇧🇷 Português](README.pt-BR.md) · 🇺🇸 English

> **The disk cleaner built for developers.** Recover 20-100 GB from Xcode, Docker, node_modules and build caches, safely. → [harbofly.app](https://harbofly.app)

A macOS menu-bar app that **finds on its own** what's eating your disk and lets you clean it in one click, with zero path configuration.

It was born from a real pain: an iOS/Android dev Mac piles up tens of GB of build artifacts and caches (`build/`, `.build/`, `node_modules/`, `DerivedData`, SPM/Homebrew/Yarn/pip caches…) that nobody remembers to clean. Harbofly scans those places automatically, shows how much you can recover, and groups everything by risk level, and, by default, **sends it all to the Trash** (so you can restore it).

Free · Open source · Apple-notarized · Privacy-first (opt-in, anonymous analytics).

## Featured

Listed on **[Awesome Mac](https://github.com/jaywcjlove/awesome-mac)**, the curated directory of standout macOS apps, and shared by its maintainer [@jaywcjlove](https://twitter.com/jaywcjlove). It's described there as *"a menu bar app that auto-discovers and frees the disk space dev build artifacts and caches hog."*

## Install

```bash
brew install --cask carloshpdoc/tap/harbofly
```

Or download the notarized `.dmg` at **[harbofly.app](https://harbofly.app)**.

## CLI

The app binary doubles as a CLI — the Homebrew install exposes it as `harbofly`:

```bash
harbofly scan                # list caches/artifacts with size and risk tier
harbofly scan --json         # machine-readable output
harbofly clean --dry-run     # preview what a safe clean would move to the Trash
harbofly clean               # move every 🟢 safe item to the Trash
harbofly clean --stale-only  # only artifacts from projects idle for 90+ days
```

The CLI only ever touches the 🟢 safe tier and always goes through the Trash.
Installed from the DMG? Run `/Applications/Harbofly.app/Contents/MacOS/Harbofly scan`.

## Features

- **Auto-discovery**: scans `~/Development` for `build`, `.build`, `node_modules`, `Pods`, `DerivedData` and the known caches in `~/Library`. Zero path config.
- **Disk bar** at the top, colored by pressure: green → orange (<20%) → **red (<10%)**.
- **"Recoverable: X GB"**: the total you can free right now.
- **Risk tiers:**
  - 🟢 **Safe**: regenerates itself on the next build.
  - 🟡 **Caution**: rebuilds, but it costs (recompiling from scratch, re-downloading device symbols).
  - 🔵 **Informative**: large folders it shows just so you know where the space is, but **never deletes** (CoreSimulator, Application Support, Downloads).
- **Trash-first by default**: restorable. **Permanent delete** exists, but it's opt-in and you confirm first.
- **Each item shows** its name, full path, and what it is.
- **"Select safe"** checks the whole safe tier at once.
- **Low-space notification**: warns you when free space drops below the threshold you pick (5/10/15/20%).
- **Automatic rescan** every 30 min + a manual button.
- **Auto-update** via [Sparkle](https://sparkle-project.org): notifies you when a new version ships (can be turned off).

## Safety

Since it's a tool that deletes files, it's built to be trustworthy:

- **Default = Trash** (restorable); nothing risky is pre-selected; confirmation before any deletion.
- **Open source end to end**: you can audit exactly what leaves your machine. Analytics is **opt-in and off by default** (via [TelemetryDeck](https://telemetrydeck.com)); when on, it sends only anonymous, aggregate usage stats (events, GB recovered, cache categories) — never your email, IP, name, paths, or project names. Toggle it anytime in preferences.
- **Signed with a Developer ID + notarized** by Apple; **build provenance (SLSA)** on every release, verifiable with `gh attestation verify Harbofly.dmg --repo carloshpdoc/Harbofly`.

## What it scans

**`~/Development`** (auto-discovery, up to depth 3):
`build`, `.build`, `node_modules`, `Pods`, `DerivedData`, all classified 🟢 Safe.

**`~/Library`** (known targets):

| Path | Tier | What it is |
|------|------|------------|
| `Developer/Xcode/DerivedData` | 🟢 | Xcode build intermediates |
| `Developer/XcodeBuildMCP/workspaces` | 🟢 | XcodeBuildMCP workspaces |
| `Caches/org.swift.swiftpm` | 🟢 | Swift Package Manager cache |
| `Caches/Homebrew` | 🟢 | Homebrew downloads |
| `Caches/Yarn` | 🟢 | Yarn cache |
| `Caches/pip` | 🟢 | pip cache |
| `Developer/Xcode/iOS DeviceSupport` | 🟡 | Device symbols (recreated when you plug in an iPhone) |
| `Caches/ms-playwright` | 🟡 | Browsers downloaded by Playwright |
| `Caches/Google` | 🟡 | Google/Chrome cache |

**Informative (read-only, never deleted):** `Library/Developer/CoreSimulator`, `Library/Application Support`, `Downloads`.

Items under 10 MB are ignored to reduce noise. The targets live in `scanDevelopment()`, `scanLibrary()` and `scanInfo()` in `Sources/Harbofly/App.swift`, easy to tweak.

## Requirements

- macOS 14+ (Sonoma)
- Apple Silicon
- Swift 6 (Xcode toolchain)

## Build & Run

```bash
# Builds signed Harbofly.app and prints where it landed
./make-app.sh

# Open it (the icon shows up in the menu bar)
open Harbofly.app
```

To distribute outside the Mac App Store (sign with Developer ID, notarize, staple and build the styled `.dmg`):

```bash
# needs SIGN_ID, ASC_KEY_ID and ASC_ISSUER_ID in the env + the .p8 in ~/.appstoreconnect/private_keys/
./make-dmg.sh   # produces a ready-to-distribute Harbofly.dmg
```

Official releases go out via **GitHub Actions** when you push a `vX.Y.Z` tag: build + notarization + build provenance + `.dmg` + Sparkle appcast + automatic cask bump in the tap.

During development:

```bash
xcrun swift build            # debug
xcrun swift run              # run directly (no .app; Sparkle stays inert)
xcrun swift build -c release # release
```

## Versioning

- User-facing SemVer in the `VERSION` file (single source of truth).
- Monotonic build number = commit count (`git rev-list --count HEAD`).

## Structure

```
Harbofly/
├── Package.swift                 # SwiftPM (macOS 14+) + Sparkle dependency
├── Sources/Harbofly/App.swift    # the whole app: scanner + UI (display name in AppInfo.name)
├── Assets/                       # icon art (HarboflyIcon.png) + Harbofly.icns
├── VERSION                       # user-facing SemVer
├── appcast.xml                   # Sparkle update feed (generated on release)
├── make-app.sh                   # builds Harbofly.app (embeds + signs Sparkle)
├── make-dmg.sh                   # signs (Developer ID) + notarizes + builds the .dmg
├── make-icon.sh                  # generates the .icns from the art
├── .github/workflows/release.yml # release CI (tag v* → build/notarize/appcast/cask)
├── SETUP-SPARKLE.md              # how to configure the auto-update keys
└── README.md
```

## Auto-update (Sparkle)

The app checks a signed (EdDSA) appcast and offers the update. It stays **inert** until the keys are configured, see [`SETUP-SPARKLE.md`](SETUP-SPARKLE.md). Homebrew users update with `brew upgrade`.
