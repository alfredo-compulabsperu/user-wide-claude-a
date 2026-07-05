# user-wide-claude-a

Portability system that syncs Claude Code artifacts (skills, commands, agents,
scripts, plugins, CLAUDE.md) from this repo to `~/.claude/` on any machine.

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

## Key Files

| File | Role |
|------|------|
| `manifest.yaml` | Source of truth — lists every artifact to sync |
| `sync.sh` | Sync engine — reads manifest, copies to `~/.claude/` |
| `docs/RUNBOOK.md` | Operational procedures (drift recovery, plugin failures) |
| `docs/CONTRIBUTING.md` | Dev setup, code style, how to add a new artifact |
| `docs/PLAN.md` | Backlog of skills/commands planned but not yet built |
| `.claude/plans/`, `.claude/prds/` | Planning docs for this repo's own artifacts |
| `research/<topic>/` | Saved research findings (see global Research Persistence rule) |
| `.claude/skills/promote-artifact/` | Skill: add local artifact to repo |
| `.claude/skills/validate-artifact/` | Skill: pre-promotion quality gate |

## Manifest Sections

`skills`, `commands`, `agents`, `scripts`, `plugins`, `claude_md` → maps 1:1 to
`~/.claude/` subdirectories. Adding an entry without the file causes `[MISSING]` in dry-run.

## Testing

No central runner. Each file is self-checking (exits 0/1):

```bash
bash .claude/tests/scripts/<name>.test.sh
```

## Gotchas

- Default `idempotency: skip` — SHA-256 mismatch is silently skipped unless `--force`
- This repo's `manifest.yaml` currently sets `idempotency: prompt` — `bash sync.sh` will interactively `read -rp` on any SHA-256 mismatch. Use `--dry-run` or `--force` in non-interactive/hook contexts.
- `claude_md.portable: false` — this file is NOT synced to `~/.claude/CLAUDE.md`; edits here only affect this repo
- Adding a file under `.claude/commands|skills|agents|scripts/` without a matching `manifest.yaml` entry means it's silently never synced — `--dry-run` won't flag it either. Use `/promote-artifact` to add the entry.
- `python3` and `sha256sum` (or `shasum`) must be on PATH before sync runs
- Plugins require `claude` CLI on PATH; install failures retry 3× with backoff
