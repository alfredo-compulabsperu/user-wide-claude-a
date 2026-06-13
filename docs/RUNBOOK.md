# Runbook: User-Wide Claude Artifact Portability

## New Machine Setup

Full artifact parity from scratch:

```bash
git clone <repo-url> ~/user-wide-claude-a
cd ~/user-wide-claude-a
bash sync.sh
```

Expected time: < 5 minutes.

## Check Sync Status (dry-run)

```bash
bash sync.sh --dry-run
```

Output legend:

| Label | Meaning |
|-------|---------|
| `[OK]` | Artifact matches repo SHA-256 — no action needed |
| `[MISSING]` | Artifact in manifest but not in `~/.claude/` |
| `[STALE]` | Artifact present but SHA-256 differs from repo |
| `[SKIP]` | SHA-256 differs; skipped per idempotency policy |
| `[LOCAL_ONLY]` | Artifact in `~/.claude/` not listed in manifest |
| `[MISSING_PLUGIN]` | Plugin in manifest not found in installed plugins |

## Force Overwrite

```bash
bash sync.sh --force
```

Use when `[STALE]` entries should be overwritten without prompting.

## Promote a Local-Only Artifact

When `--dry-run` reports `[LOCAL_ONLY]` entries:

```bash
# Local install + manifest update only
/promote-artifact ~/.claude/<type>s/<artifact-name>

# Full git pipeline (branch → commit → push → PR → squash-merge)
/promote-artifact ~/.claude/<type>s/<artifact-name> --git
```

## Validate an Artifact Before Promotion

```bash
/validate-artifact <path>
```

Checks: no machine-specific paths, all dependencies resolvable, terseness ≥ 7/10.

## Manifest Drift Recovery

If `manifest.yaml` drifts from actual `~/.claude/` state:

1. Run `bash sync.sh --dry-run` to identify gaps.
2. For missing entries: run `/promote-artifact` to add them.
3. For stale entries: run `bash sync.sh --force` to overwrite.

## Plugin Install Failures

If `[MISSING_PLUGIN]` persists after `bash sync.sh`:

```bash
claude plugin install <id> --marketplace <marketplace>
```

Verify `claude` CLI is on PATH and `gh auth status` passes.

## Common Issues

| Symptom | Fix |
|---------|-----|
| `ERROR: python3 required` | `sudo apt install python3` |
| `ERROR: sha256sum or shasum not found` | Install `coreutils` |
| `ERROR: gh not found` | Install GitHub CLI: `gh.releases.page` |
| `ERROR: manifest validation failed` | Run `python3 -c "import yaml; yaml.safe_load(open('manifest.yaml'))"` — fix reported YAML errors |
| Plugin install retries failing | Check internet connection; re-run `bash sync.sh` |
