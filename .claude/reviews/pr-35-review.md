# PR Review: #35 — feat(skills): add gh-issue-create skill

**Reviewed**: 2026-07-27
**Author**: alfredo-compulabsperu
**Branch**: worktree-gh-create-issue → develop
**Decision**: APPROVE

## Summary
Adds a complete `gh-issue-create` skill: draft → dual-agent review (mechanical + KISS/SRP/YAGNI/DRY) → publish pipeline for GitHub issue creation, with bundled templates, rules, an `--install` bootstrap mode, and an MCP/gh-CLI fallback for issue creation. Manifest and settings changes register it correctly and rebase-merge cleanly onto current `develop`. No stub sections, no TODOs, no machine-specific content.

## Findings

### CRITICAL
None.

### HIGH
None.

### MEDIUM
None.

### LOW
- `SKILL.md` "Bundled Asset Paths" table hardcodes `~/.claude/...` paths with a worktree-relative fallback note — correct behavior, but relies on the model reading the caveat rather than a path variable. Acceptable given this repo's existing skill conventions (same pattern used elsewhere).

## Validation Results

| Check | Result |
|---|---|
| Type check | Skipped — no package.json/Cargo.toml/go.mod/pyproject.toml (markdown/YAML artifact repo) |
| Lint | Skipped — no applicable linter |
| Tests | Skipped — no test suite covers skill content; `evals/evals.json` provides skill-level eval scenarios (3 cases: install+bug, feature dry-run, multi-topic SRP split) |
| Build | N/A |

## Files Reviewed
- `.claude/skills/gh-issue-create/SKILL.md` (Added) — full read, coherent and complete
- `.claude/skills/gh-issue-create/bundled/rules/gh-issue-rules.md` (Added) — full read
- `.claude/skills/gh-issue-create/bundled/templates/bug.yml` (Added) — full read
- `.claude/skills/gh-issue-create/bundled/templates/chore.yml` (Added) — full read
- `.claude/skills/gh-issue-create/bundled/templates/feature.yml` (Added) — full read
- `.claude/skills/gh-issue-create/evals/evals.json` (Added) — full read
- `manifest.yaml` (Modified) — registers `gh-issue-create` under `skills:`, merged cleanly alongside 6 other skills added upstream since this branch forked
- `.claude/settings.json` (Modified) — enables `github` and `skill-creator` plugins (dev-time tooling used to build/test the skill), merged cleanly alongside upstream's `skill-creator` addition

## Notes
- `.claude/skills/gh-issue-create-workspace/` (skill-creator iteration/eval/benchmark scratch data) was deliberately left uncommitted, matching this repo's existing convention for `-workspace` dev dirs (e.g. `review-plan-workspace` is untracked in the main checkout).
- Branch was 13 commits behind `develop` at PR-open time, causing a real merge conflict in `manifest.yaml`'s `skills:` list and `.claude/settings.json`'s `enabledPlugins` (both list-append conflicts from parallel skill work). Resolved via rebase, keeping both sides' entries; PR is now `MERGEABLE`/`CLEAN`.
