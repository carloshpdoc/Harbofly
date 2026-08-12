# Harbofly Cleanup — agent skill

Let a coding agent (Claude Code, Codex, or any AGENTS-aware / rules-based tool)
reclaim disk space on a macOS dev machine with the [Harbofly](https://harbofly.app)
CLI — safely, everything to the Trash.

This folder ships the same guidance in two formats:

- **`SKILL.md`** — Anthropic Agent Skill (frontmatter + body) for Claude Code.
- **`AGENTS.md`** — plain instruction file for Codex and other AGENTS.md-aware tools.

Both wrap the `harbofly` CLI (`scan` / `clean` / `dups`), which is the same
binary as the app, so it always matches the installed version.

## Prerequisite

Install Harbofly (exposes the `harbofly` command):

```bash
brew install --cask carloshpdoc/tap/harbofly
harbofly version
```

Or invoke the bundled binary directly: `/Applications/Harbofly.app/Contents/MacOS/Harbofly`.

## Install per agent

### Claude Code
Copy the `harbofly-cleanup/` folder into your skills directory:

```bash
# personal (all projects)
cp -R harbofly-cleanup ~/.claude/skills/
# or project-scoped
cp -R harbofly-cleanup .claude/skills/
```

Claude auto-discovers it from the `description` in `SKILL.md`. Trigger it by
asking to "free up disk space" / "clean dev caches", or run `/harbofly-cleanup`.

### Codex (and other AGENTS.md tools)
Place `AGENTS.md` where Codex reads it — the root of the repo/working directory
it operates in (Codex loads `AGENTS.md` automatically). For a **scheduled Codex
task**, point the task at a directory containing this `AGENTS.md`, then prompt
it with something like *"free up disk space with harbofly, stale projects only"*.

### Cursor / other rules-based agents
Paste the body of `SKILL.md` (or `AGENTS.md`) into the tool's rules/system-prompt
file (e.g. a Cursor rule). The instructions are self-contained.

## Safety

- `harbofly clean` only ever touches the 🟢 safe tier and always moves items to
  the **Trash** (recoverable). 🟡/🔵 tiers and Docker are left alone.
- `harbofly dups --permanent` is the only path that bypasses the Trash — the
  skill treats it as destructive and requires explicit confirmation.
- Targets flagged `"unsavedWork": true` are stale projects that still hold
  uncommitted or unpushed git work — never cleaned without confirmation.
