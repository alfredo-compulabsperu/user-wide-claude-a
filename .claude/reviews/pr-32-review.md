# PR Review: #32 — feat(sync): add three-way divergence detection for out-of-band ~/.claude/ edits

**Reviewed**: 2026-07-26
**Author**: alfredo-compulabsperu
**Branch**: worktree-import → develop
**Decision**: APPROVE

## Summary
Adds a per-machine baseline (`~/.claude/.sync-state.json` via new `.claude/scripts/sync-state.sh`) so `sync.sh` and `promote-artifact` can tell an out-of-band hand-edit of a `~/.claude/` artifact (`[DIVERGED]`) apart from ordinary repo-moved-on drift, and gates the former behind an explicit `--force-diverged`/interactive confirm rather than plain `--force`. Also fixes a real, previously-dead-code stdin-shadowing bug in `sync.sh`'s install loops, and adds a fourth "Coherent" check to `validate-artifact`. Implementation is careful, faithfully follows its own plan (`.claude/plans/sync-state-divergence-detection.plan.md`), and ships full test coverage. Read every changed file in full; no CRITICAL or HIGH issues found.

## Findings

### CRITICAL
None.

### HIGH
None.

### MEDIUM
None.

### LOW
- `sync.sh` diverged-branch `diff -u`/`diff -rq` output is unbounded — fine at this repo's artifact sizes, would be noisy on a very large file/dir. Not worth guarding against given current usage.
- `promote-artifact/SKILL.md` uses a `repo:<type>s/<name>` key prefix for the repo destination (vs. sync.sh's bare `<type>s/<name>` for local) to avoid the two destinations colliding on one baseline — correct and necessary, but only documented inline in the SKILL.md, not called out in the plan. Worth a one-line mention next time a plan touches shared keying, purely for plan/impl traceability.

## Validation Results

| Check | Result |
|---|---|
| `bash -n` (sync-state.sh, sync.sh, both new test files) | Pass |
| `sync-state.test.sh` | Pass (10/10) |
| `sync.test.sh` | Pass (10/10) |
| Full regression, all 7 `.claude/tests/scripts/*.test.sh` | Pass (68/68 total, 0 failures) |
| `bash sync.sh --dry-run` against real `~/.claude/` | Pass — clean, `diverged: 0` (no prior baselines, confirms documented no-false-positive-on-rollout behavior), zero writes |
| Type check / lint / build | N/A — no `package.json`/`Cargo.toml`/`go.mod`/`pyproject.toml`; project is bash scripts + markdown skills, substituted with `bash -n` + repo's own test harness above |
| `manifest.yaml` untouched | Confirmed (empty diff) |

## Files Reviewed
- `.claude/plans/index.md` — Modified (status row)
- `.claude/plans/sync-state-divergence-detection.plan.md` — Added (plan artifact)
- `.claude/scripts/sync-state.sh` — Added
- `.claude/skills/promote-artifact/SKILL.md` — Modified (Step 4 rewrite, `--force-diverged` arg)
- `.claude/skills/validate-artifact/SKILL.md` — Modified (new Coherent check)
- `.claude/tests/scripts/sync-state.test.sh` — Added
- `.claude/tests/scripts/sync.test.sh` — Added
- `CLAUDE.md` — Modified (repo-internal-tooling sentence, Gotchas row)
- `sync.sh` — Modified (three-way check, `--force-diverged`, fd-3 stdin fix)
