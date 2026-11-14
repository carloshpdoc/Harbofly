---
name: harbofly-cleanup
description: >-
  Reclaim disk space on a macOS developer machine by finding and safely
  cleaning build caches and artifacts (Xcode DerivedData, node_modules, Docker,
  and package-manager/editor/AI caches) with the Harbofly CLI. Everything goes
  to the Trash and is recoverable. Use when the user wants to free up disk
  space, clean dev caches, find duplicate files, see what is on an
  external drive or USB stick, or set up automated cleanup.
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
- **`compare --apply` removes from the target disk only files proven to exist
  on another one**, byte for byte, with the surviving copy outside the target. It
  refuses read-only, network and Time Machine volumes outright. It re-checks size
  and mtime immediately before each removal and skips anything that changed since
  the scan.
- **A disk may have no Trash** (`"trash": false` in `harbofly volumes --json`).
  There, removal is permanent even without `--permanent`. Say so before acting.
- **Watch `mediaAtRisk`** in `compare --json`: those are photo/video files whose
  only other copy is the one being deleted. Deleting them loses nothing today and
  leaves the content with a single copy in the world. Always surface this count.
- **Never delete from `only here`** — that bucket is what exists nowhere else.
- **Check `coverageOK`** before trusting any count. If it is false, or
  `hashErrors` is above zero, files were not accounted for: report it instead of
  presenting the numbers as complete.
- **`verifyMismatches` above zero means same hash, different bytes.** That should
  be impossible — stop and tell the user to suspect the disk or the cable.

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

## Connected-disk workflow

For an external drive, a USB stick or any mounted volume:

1. **List** what is attached: `harbofly volumes --json`. Skip anything whose
   `tier` is not `scannable`.
2. **Read** the disk: `harbofly index "<path>" --json`. Check `coverageOK`
   first, then report where the bulk is (`byFolder`, `byExtension`) and the gap
   between `bytesLogical` and `bytesAllocated` if it is large.
3. **Compare** against the others: `harbofly compare "<path>" --json`.
   Report the three buckets separately — already elsewhere / repeated inside /
   only here — and never blur them together.
4. **Surface the risks**: `mediaAtRisk`, a `trash: false` disk, and
   `uniqueBytes` (what a migration must carry).
5. **Confirm**, then `compare "<path>" --apply`. Prefer `--subtrees` in the
   preview so whole duplicated folders read as one decision instead of hundreds.

## Commands

```
harbofly scan  [--json]                 list caches/artifacts w/ size + risk tier
harbofly clean [--dry-run]              move all 🟢 safe items to the Trash
               [--stale-only]           …only from projects idle 90+ days
harbofly dups  [folders...]             find duplicate files by content (SHA-256
               [--apply]                + byte-verify); --apply trashes non-keepers
               [--permanent]            delete instead of Trash (destructive)
               [--json]                 no folders = Downloads/Documents/Desktop/Pictures
harbofly volumes [--json]               list mounted disks (size, free, fs, flags)
                 [--all]                …including read-only ones (mounted .dmg)
harbofly index <path> [--json]          inventory of a disk or folder: coverage,
                                        space, by folder/extension/size
harbofly compare <vol> [other…]         what on <vol> already exists elsewhere,
                 [--subtrees]           what repeats inside it, what is only there
                 [--only-unique]        no other volume given = all mounted ones
                 [--apply]              removes ONLY what was proven to exist
                 [--permanent]          elsewhere (destructive without Trash)
                 [--json]
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

`harbofly volumes --json`:

```json
{
  "volumes": [
    {
      "name": "T7 Shield",
      "path": "/Volumes/T7 Shield",
      "fs": "exfat",
      "totalBytes": 0,
      "freeBytes": 0,
      "tier": "scannable",
      "internal": false,
      "removable": false,
      "readOnly": false,
      "timeMachine": false,
      "trash": true
    }
  ]
}
```

`tier` is `scannable` | `readOnly` | `protected`. Only `scannable` accepts
deletion; `protected` means read-only, network or a Time Machine destination.

`harbofly index --json` — the coverage gate is the part that matters:
`indexed + sum(skipped) + sum(errors) == enumerated`, and `coverageOK` says so.
`skipped` and `errors` are keyed by reason (`tooSmall`, `symlink`, `package`,
`volumeMetadata`, `appleDouble`, `junk` / `stat`, `enumerator`). Also carries
`bytesLogical` vs `bytesAllocated` (they diverge a lot on exFAT: cluster slack),
plus `byFolder`, `byExtension`, `bySize` and `metadata`.

`harbofly compare --json`:

```json
{
  "target": "/Volumes/T7 Shield",
  "others": ["/"],
  "coverageOK": true,
  "hashErrors": 0,
  "verifyMismatches": 0,
  "sharedFiles": 0,
  "sharedBytes": 0,
  "internalFiles": 0,
  "internalBytes": 0,
  "uniqueFiles": 0,
  "uniqueBytes": 0,
  "mediaAtRisk": 0,
  "subtrees": [{ "path": "/Volumes/T7 Shield/arvore", "files": 0, "bytes": 0 }],
  "shared": [
    { "path": "…", "bytes": 0, "sha256": "…", "keeper": "/path/kept",
      "keeperVolume": "Macintosh HD", "copies": 2, "lastBackupOfMedia": false }
  ]
}
```

`shared` is capped at 5000 rows; the totals are always complete.

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
