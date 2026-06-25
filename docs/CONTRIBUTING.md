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
| `bash sync.sh --force` | Overwrite existing files even when SHA-256 differs (no prompt) |
<!-- END AUTO-GENERATED -->

## Slash Commands

<!-- AUTO-GENERATED: from commands/ and skills/ -->
| Trigger | Description |
|---------|-------------|
| `/vm-health` | Run VM health checks (disk, CPU, memory); prints verbatim output from `vm-health.sh` |
| `/validate-artifact <path>` | Validate an artifact for portability, dependency completeness, and terseness |
| `/promote-artifact <path> [--type] [--force] [--git]` | Validate and install artifact locally and into the repo; `--git` runs full PR pipeline |
<!-- END AUTO-GENERATED -->

## Testing

No automated test suite. Validation steps:

```bash
python3 -c "import yaml; yaml.safe_load(open('manifest.yaml')); print('manifest: OK')"
bash -n sync.sh && echo "sync.sh: OK"
ls .claude/skills/validate-artifact/SKILL.md && echo "validate-artifact: OK"
ls .claude/skills/promote-artifact/SKILL.md && echo "promote-artifact: OK"
```

## Adding a New Artifact

1. Place the artifact under the correct directory (`.claude/skills/`, `.claude/commands/`, `.claude/agents/`, `.claude/scripts/`).
2. Run `/promote-artifact <path>` (or `/promote-artifact <path> --git` to open a PR).
3. The skill updates `manifest.yaml` automatically.

## Code Style

- Bash: `set -euo pipefail`, quote all variable expansions, no global state side-effects.
- YAML: 2-space indent, single-quoted strings for env vars.
- Skill `.md`: frontmatter required (`name`, `description`, `triggers`, `args`).
