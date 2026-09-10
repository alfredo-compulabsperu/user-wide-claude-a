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

<!-- AUTO-GENERATED: from the [LABEL] strings sync.sh emits -->
| Label | Meaning |
|-------|---------|
| `[OK]` | Artifact matches repo SHA-256 — no action needed |
| `[MISSING]` | Artifact in manifest but not in `~/.claude/` |
| `[STALE]` | Artifact present but SHA-256 differs from repo (repo changed since last sync) |
| `[DIVERGED]` | Destination was edited out-of-band since the last sync — `--force` will not touch it; needs `--force-diverged` |
| `[SKIP]` / `[SKIPPED]` | SHA-256 differs; skipped per idempotency policy or user answer |
| `[INSTALLED]` / `[UPDATED]` | Written this run (new / replaced) |
| `[LOCAL_ONLY]` | Artifact in `~/.claude/` not listed in manifest |
| `[MISSING_PLUGIN]` | Plugin in manifest not found in installed plugins |
<!-- END AUTO-GENERATED -->

Manifest sections scanned: `skills`, `commands`, `agents`, `rules`, `hooks`, `lazy`, `scripts`, `output_styles`, `claude_md`, `plugins`. `rules` scans `~/.claude/rules/` one level deep, so a rule an installer drops under `rules/ecc/**` is not reported as `[LOCAL_ONLY]`.

## Force Overwrite

```bash
bash sync.sh --force            # overwrite [STALE] without prompting; leaves [DIVERGED] alone
bash sync.sh --force-diverged   # also overwrite [DIVERGED] — you lose the out-of-band edit
```

Before `--force-diverged`, diff the destination against the repo copy; if the out-of-band edit is wanted, bring it into the repo first (`/promote-artifact` or a plain copy) so the overwrite is a no-op.

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

## Hooks and Lazy Rules

`hooks` entries install to `~/.claude/hooks/` (chmod +x); registration lives in `~/.claude/settings.json`, which is not synced. `lazy` entries install under `~/.claude/lazy/`; `lazy/rules/*.md` carry an `on:` frontmatter block (tools, paths, commands) read by `hooks/lazy-rule-inject.py` on `PreToolUse`, which injects the body before the action, once per `(rule, subject)` per session.

**Adding or changing a hook — order matters.** Registration in `settings.json` is live on the next tool call, and a registered script that does not exist exits 2, which Claude Code treats as a deny on every matched tool. Always: install the file (`bash sync.sh`) → check it on a piped payload → register it. To remove: unregister → delete.

**Testing rule changes in this repo.** `.claude/settings.json` here points `LAZY_RULE_INJECT_RULE_DIRS` at the repo's own `.claude/rules` and `.claude/lazy/rules`, so sessions started in this repo get injections from the repo copies without syncing. The injector script itself still runs from `~/.claude/hooks/`, so script changes need `bash sync.sh` plus `python3 -m pytest .claude/hooks/tests/`.

Design notes and measurements: `docs/rule-loading-audit.md`.

## Common Issues

| Symptom | Fix |
|---------|-----|
| Every Bash/Edit/Write call denied with `can't open file '.../hooks/<name>.py'` | A hook is registered in `~/.claude/settings.json` but the file is missing — run `bash sync.sh` (or unregister it), then retry the tool call |
| A `paths:`-gated rule never loads | Native `paths:` gating only matches files inside the project root and only on Read; give the rule an `on:` block so the injector serves it (see `docs/rule-loading-audit.md` §2) |
| `ERROR: python3 required` | `sudo apt install python3` |
| `ERROR: sha256sum or shasum not found` | Install `coreutils` |
| `ERROR: gh not found` | Install GitHub CLI: `gh.releases.page` |
| `ERROR: manifest validation failed` | Run `python3 -c "import yaml; yaml.safe_load(open('manifest.yaml'))"` — fix reported YAML errors |
| Plugin install retries failing | Check internet connection; re-run `bash sync.sh` |
