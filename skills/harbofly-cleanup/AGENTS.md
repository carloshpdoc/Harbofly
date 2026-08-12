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

## Commands

```
harbofly scan  [--json]
harbofly clean [--dry-run] [--stale-only]
harbofly dups  [folders...] [--apply] [--permanent] [--json]
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
