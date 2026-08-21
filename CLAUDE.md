# user-wide-claude-a

Portability system that syncs Claude Code artifacts (skills, commands, agents,
scripts, output styles, plugins, CLAUDE.md) from this repo to `~/.claude/` on any machine.

## Key Commands

```bash
bash sync.sh              # Install / update artifacts from manifest.yaml
bash sync.sh --dry-run    # Report what would change (safe, no writes)
bash sync.sh --force      # Overwrite stale artifacts without prompting
```

## Artifact Lifecycle

| Action | Command |
|--------|---------|
| Add artifact found in `~/.claude/` to this repo | `/promote-artifact ~/.claude/<type>s/<name>` |
| Add + open full git pipeline (branch → PR) | `/promote-artifact ... --git` |
| Validate artifact before promotion | `/validate-artifact <path>` |
| Extract one tool from an installed plugin (not the whole plugin) | `/copy-plugin-tool --plugin <hint> --tools <hint>` |

`promote-artifact`, `validate-artifact`, and `.claude/scripts/sync-state.sh` are repo-internal tooling for
maintaining *this* repo's own artifact pipeline — deliberately absent from `manifest.yaml`/sync. Do not add
manifest entries for them; that's not an oversight. `copy-plugin-tool` is a general-purpose skill and ships
via `manifest.yaml` like any other.

## Key Files

| File | Role |
|------|------|
| `manifest.yaml` | Source of truth — lists every artifact to sync |
| `sync.sh` | Sync engine — reads manifest, copies to `~/.claude/` |
| `docs/RUNBOOK.md` | Operational procedures (drift recovery, plugin failures) |
| `.claude/skills/promote-artifact/` | Skill: add local artifact to repo |
| `.claude/skills/validate-artifact/` | Skill: pre-promotion quality gate |
| `.claude/skills/copy-plugin-tool/` | Skill: extract one tool from an installed plugin |

## Manifest Sections

`skills`, `commands`, `agents`, `scripts`, `output_styles`, `plugins`, `claude_md` → maps 1:1 to
`~/.claude/` subdirectories. Adding an entry without the file causes `[MISSING]` in dry-run.

## GitHub Issue Creation
Always use `/gh-issue-create` when opening GitHub issues. Never run `gh issue create` directly.

## Gotchas

- Default `idempotency: skip` — SHA-256 mismatch is silently skipped unless `--force`
- `python3` and `sha256sum` (or `shasum`) must be on PATH before sync runs
- Plugins require `claude` CLI on PATH; install failures retry 3× with backoff
- `~/.claude/.sync-state.json` tracks the last-synced SHA-256 per artifact (three-way divergence
  detection) — don't hand-edit or delete it; `sync.sh`/`promote-artifact` self-heal it on every run
