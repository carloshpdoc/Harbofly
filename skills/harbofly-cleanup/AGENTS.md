# AGENTS.md — Harbofly disk cleanup

Instructions for coding agents (Codex and AGENTS.md-aware tools) operating in
this environment. You can reclaim disk space on this macOS machine with the
`harbofly` CLI. It is the same binary as the Harbofly app, so it always matches
the installed version.

## Before you clean

- Check availability: `harbofly version`. If not on PATH, the binary is at
  `/Applications/Harbofly.app/Contents/MacOS/Harbofly`. If neither exists, stop
  and tell the user to install it (`brew install --cask carloshpdoc/tap/harbofly`).
- The CLI `clean` **only touches the 🟢 safe tier** and **always uses the Trash**
  (recoverable). It never touches 🟡 caution or 🔵 info tiers, and it skips
  Docker. Only `dups --permanent` deletes without the Trash — treat that as
  destructive.
- On a connected disk, `compare --apply` removes **only** files proven byte for
  byte to exist on another volume, with the surviving copy outside the target. It
  refuses read-only, network and Time Machine volumes, and re-checks size and
  mtime right before each removal, skipping whatever changed since the scan.
- Some disks have **no Trash** (`"trash": false` in `harbofly volumes --json`).
  There, removal is permanent even without `--permanent`. Say so first.
- Before trusting any count, check `coverageOK` and `hashErrors` in the JSON. If
  coverage is false or there are hash errors, files were not accounted for —
  report that instead of presenting the numbers as complete. `verifyMismatches`
  above zero means same hash with different bytes: stop, and tell the user to
  suspect the disk or the cable.
- `mediaAtRisk` counts photo/video files whose only other copy is the one being
  deleted. Always surface it. Never delete anything from the `only here` bucket.

## Interactive use

1. `harbofly scan --json` — parse it.
2. Report free/total disk, total reclaimable (🟢 + 🟡 `bytes`), and the biggest
   items. Any target with `"unsavedWork": true` is a stale project with
   uncommitted/unpushed git work — surface it and do not clean it without
   explicit confirmation.
3. `harbofly clean --dry-run` — show what would be trashed.
4. Get confirmation.
5. `harbofly clean` (all 🟢 safe) or `harbofly clean --stale-only` (idle 90+ days).

Never run a real `clean`, `dups --apply`, or `dups --permanent` without a
dry-run preview and confirmation — unless the user has explicitly set up
unattended cleanup (below).

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
harbofly scan  [--json]
harbofly clean [--dry-run] [--stale-only]
harbofly dups  [folders...] [--apply] [--permanent] [--json]
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

`scan --json` → `{ freeBytes, totalBytes, targets: [{ label, path, tier:
"safe"|"caution"|"info", bytes, staleDays?, unsavedWork?, docker? }] }`

`dups --json` → `{ reclaimableBytes, groups: [{ hash, size, reclaimable,
keeper, duplicates: [paths] }] }`

## Unattended / scheduled runs

Safe by design because everything is recoverable from the Trash. For a nightly
job, prefer the narrowest scope:

```bash
harbofly clean --stale-only >> ~/harbofly-nightly.log 2>&1   # only idle 90+ day projects
harbofly clean            >> ~/harbofly-nightly.log 2>&1     # all 🟢 safe items
```

Do not put `dups --permanent` in automation.
