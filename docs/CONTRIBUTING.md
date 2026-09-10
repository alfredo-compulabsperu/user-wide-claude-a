# Contributing Guide

Solo developer repo — no external contributors. These notes document local workflows.

## Prerequisites

- Linux (only supported platform)
- `bash`, `python3` (stdlib `yaml` — install `python3-yaml` if missing)
- `git`, `gh` (GitHub CLI) — required only for `/promote-artifact --git`
- `sha256sum` or `shasum`
- Claude Code CLI (`claude`) — required for plugin install

## Development Setup

```bash
git clone <repo-url>
cd user-wide-claude-a
bash -n sync.sh   # syntax check
```

No package install step. No build step.

## Scripts

For full flag reference: `bash sync.sh --help`

<!-- AUTO-GENERATED: from sync.sh usage() -->
| Command | Description |
|---------|-------------|
| `bash sync.sh` | Install all artifacts from repo to `~/.claude/` |
| `bash sync.sh --dry-run` | Report missing/stale/local-only artifacts without modifying `~/.claude/` |
| `bash sync.sh --force` | Overwrite existing files even when SHA-256 differs (no prompt); never touches `[DIVERGED]` |
| `bash sync.sh --force-diverged` | Also overwrite destinations edited out-of-band since the last sync |
| `bash .claude/tests/run-all.sh` | Run every bash test suite under `.claude/tests/scripts/` |
| `python3 -m pytest .claude/hooks/tests/` | Run the hook tests (`lazy-rule-inject.py`) |
<!-- END AUTO-GENERATED -->

## Slash Commands

<!-- AUTO-GENERATED: from the description: frontmatter of .claude/commands/*.md and .claude/skills/*/SKILL.md -->
| Trigger | Description |
|---------|-------------|
| `/open-claude` | Open a new Claude Code session, in a named tmux window when inside tmux |
| `/open-gh-issue` | Output GitHub issue URLs by ID(s) or natural-language search |
| `/open-gh-pr` | Output GitHub pull request URLs by ID(s) |
| `/rename-tmux-window [name]` | Rename the current tmux window; defaults to branch/worktree name |
| `/session-summary` | Plain-English summary of the current session (default/`--extra`/`--full`) |
| `/vm-cleanup` | Scan and clean dev VM disk consumers (apt, journald, npm, node_modules, worktrees, Trash, snap, nvm) |
| `/vm-health` | Report VM resource health, spot issues, recommend optimizations |
| `/catalog` | Summarize every artifact declared in `manifest.yaml`, grouped by type |
| `/copy-plugin-tool --plugin <hint> --tools <hint>` | Copy one agent/command/skill out of an installed plugin's cache into `.claude/` |
| `/execute-plan <plan>` | Drive a saved plan end-to-end to a reviewed PR via isolated per-task agents |
| `/gh-issue-create` | Create a GitHub issue with template enforcement and dual-agent draft review |
| `/gh-pr-update` | Rewrite the current branch's PR title and body to match what was actually changed |
| `/knowledge-ops` | Knowledge base management, ingestion, sync and retrieval across storage layers |
| `/pr-review [--comment]` | Review a PR or diff by domain, deferring to the repo's own domain owners |
| `/promote-artifact <path> [--type] [--force] [--git]` | Validate and install an artifact locally and into the repo; `--git` runs the PR pipeline |
| `/research-ops` | Evidence-first current-state research workflow |
| `/run-prd <prd>` | Drive a whole PRD to a reviewed PR, one plan per pending milestone |
| `/ship` | Commit → push → PR create/update → optional review → merge → delete branch, one shot |
| `/validate-artifact <path>` | Validate an artifact for portability, dependency completeness, terseness and coherence |
<!-- END AUTO-GENERATED -->

## Testing

```bash
bash .claude/tests/run-all.sh              # bash suites, one per script under .claude/tests/scripts/
python3 -m pytest .claude/hooks/tests/ -q  # hook tests; black-box, drive the hook via stdin JSON
bash sync.sh --dry-run                     # must exit 0; read-only
```

Bash suites are plain scripts printing `PASS:`/`FAIL:` lines; add `.claude/tests/scripts/<name>.test.sh` for a new script and `run-all.sh` picks it up. Hook tests point the hook at per-test tmp dirs through `LAZY_RULE_INJECT_RULE_DIRS` / `LAZY_RULE_INJECT_MARKER_DIR` and never touch `~/.claude`.

## Adding a New Artifact

1. Place the artifact under the correct directory (`.claude/skills/`, `.claude/commands/`, `.claude/agents/`, `.claude/scripts/`, `.claude/rules/`, `.claude/hooks/`, `.claude/lazy/rules/`).
2. Skills, commands, agents, scripts: run `/promote-artifact <path>` (or `--git` to open a PR); it updates `manifest.yaml`.
3. Rules, hooks, lazy bodies: add the manifest entry by hand (`hooks` need `executable: true`), then `bash sync.sh`. For a hook, sync **before** registering it in `~/.claude/settings.json` — see `docs/RUNBOOK.md` § Hooks and Lazy Rules.
4. A lazy rule needs an `on:` block (`tools`, and `paths` and/or `commands` globs); test it in this repo by writing a matching file — the repo's `.claude/settings.json` serves rules from the repo copies.

## Code Style

- Bash: `set -euo pipefail`, quote all variable expansions, no global state side-effects.
- YAML: 2-space indent, single-quoted strings for env vars.
- Skill `.md`: frontmatter required (`name`, `description`, `triggers`, `args`).
