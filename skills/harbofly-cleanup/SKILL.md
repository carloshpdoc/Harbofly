---
name: harbofly-cleanup
description: >-
  Reclaim disk space on a macOS developer machine by finding and safely
  cleaning build caches and artifacts (Xcode DerivedData, node_modules, Docker,
  and package-manager/editor/AI caches) with the Harbofly CLI. Everything goes
  to the Trash and is recoverable. Use when the user wants to free up disk
  space, clean dev caches, find duplicate files, or set up automated cleanup.
---

# Harbofly Cleanup

Drive the `harbofly` CLI to scan a developer's Mac for reclaimable disk space
and clean it safely. The CLI is the same binary as the app, so it always
matches the installed version.

## Prerequisites

- Harbofly installed. Either on PATH via Homebrew
  (`brew install --cask carloshpdoc/tap/harbofly`) or invoke the binary
  directly: `/Applications/Harbofly.app/Contents/MacOS/Harbofly`.
- Confirm it runs: `harbofly version`. If missing, tell the user how to install
  it instead of guessing paths.

## Safety model (read before cleaning)

- The CLI `clean` **only ever touches the 🟢 safe tier** (regenerates on next
  build) and **always moves items to the Trash** — recoverable until emptied.
  The 🟡 caution and 🔵 info tiers are never touched by the CLI; those need the
  app UI.
- **Docker space is intentionally skipped** by the CLI (prune is irreversible).
- `dups --permanent` is the one destructive path — it bypasses the Trash.
  Treat it as delete-forever and require explicit confirmation.
- A target with `"unsavedWork": true` belongs to a stale project that still has
  **uncommitted or unpushed git work**. Never clean it without calling this out
  and getting explicit confirmation.

## Interactive workflow

1. **Scan** the machine-readable output: `harbofly scan --json`
2. **Summarize** for the user: free vs total disk, total reclaimable (sum of
   🟢 + 🟡 `bytes`), and the biggest items. Flag any `unsavedWork` targets.
3. **Preview**: `harbofly clean --dry-run` — show exactly what would go to the
   Trash (this only lists the 🟢 safe tier).
4. **Confirm** with the user.
5. **Clean**: `harbofly clean` (all 🟢 safe → Trash), or
   `harbofly clean --stale-only` (only artifacts from projects idle 90+ days).

Do not run a real `clean` / `dups --apply` / `dups --permanent` without a
dry-run preview and confirmation first — unless the user has pre-authorized
unattended cleanup (see Automated mode).

## Commands

```
harbofly scan  [--json]                 list caches/artifacts w/ size + risk tier
harbofly clean [--dry-run]              move all 🟢 safe items to the Trash
               [--stale-only]           …only from projects idle 90+ days
harbofly dups  [folders...]             find duplicate files by content (SHA-256
               [--apply]                + byte-verify); --apply trashes non-keepers
               [--permanent]            delete instead of Trash (destructive)
               [--json]                 no folders = Downloads/Documents/Desktop/Pictures
harbofly version
```

## JSON shapes

`harbofly scan --json`:

```json
{
  "freeBytes": 0,
  "totalBytes": 0,
  "targets": [
    {
      "label": "DerivedData/MyApp",
      "path": "/Users/you/Library/Developer/Xcode/DerivedData/MyApp-abc123",
      "tier": "safe",
      "bytes": 0,
      "staleDays": 120,
      "unsavedWork": true,
      "docker": true
    }
  ]
}
```

`tier` is `safe` | `caution` | `info`. `staleDays`, `unsavedWork`, and `docker`
are present only when relevant.

`harbofly dups --json`:

```json
{
  "reclaimableBytes": 0,
  "groups": [
    { "hash": "…", "size": 0, "reclaimable": 0, "keeper": "/path/kept", "duplicates": ["/path/dupe"] }
  ]
}
```

## Automated / scheduled mode

For unattended cleanup (e.g. a nightly cron job or a scheduled Codex/agent task):

- Safest recipe — only long-idle projects, always to the Trash:
  ```bash
  harbofly clean --stale-only >> ~/harbofly-nightly.log 2>&1
  ```
- Broader — every 🟢 safe item:
  ```bash
  harbofly clean >> ~/harbofly-nightly.log 2>&1
  ```
- Everything stays recoverable in the Trash until it's emptied, so unattended
  runs are safe by design. Never wire `dups --permanent` into automation.
