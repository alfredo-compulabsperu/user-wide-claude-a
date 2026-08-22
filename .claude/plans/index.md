# Plans Index

One row per plan/runbook in this directory. Keep in sync — the plans-index-guard
hook denies creating or editing a plan file not listed here, and blocks any entry
whose file has been deleted or moved.

| Plan | Milestone / Purpose | Status |
|---|---|---|
| [plan-m2-manifest.plan.md](plan-m2-manifest.plan.md) | M2 — Manifest format | complete |
| [plan-m3-sync-script.plan.md](plan-m3-sync-script.plan.md) | M3 — Sync script | complete |
| [plan-m4-validate-artifact.plan.md](plan-m4-validate-artifact.plan.md) | M4 — `/validate-artifact` skill | complete |
| [plan-m5-promote-local.plan.md](plan-m5-promote-local.plan.md) | M5 — `/promote-artifact` skill (local) | complete |
| [plan-m6-promote-git.plan.md](plan-m6-promote-git.plan.md) | M6 — `/promote-artifact` git pipeline | complete |
| [plan-m7-claude-md-portability.plan.md](plan-m7-claude-md-portability.plan.md) | M7 — CLAUDE.md portability | in-progress |
| [impl-loop-runbook.md](impl-loop-runbook.md) | Implementation loop runbook (sequential, fast mode) driving M2-M6 | complete |
| [portability-loop-runbook.md](portability-loop-runbook.md) | Loop runbook (sequential, safe mode) for the same portability PRD | complete |
| [sync-state-divergence-detection.plan.md](sync-state-divergence-detection.plan.md) | Three-way divergence detection (`sync-state.sh`) for `sync.sh` and `promote-artifact` | complete |
| [vm-cleanup-issue-36.plan.md](vm-cleanup-issue-36.plan.md) | Issue #36 — vm-cleanup.sh husk fix, depth-mismatch fix, track script in repo | complete |
| [assess-plugin-packaging-issue-42.plan.md](assess-plugin-packaging-issue-42.plan.md) | Issue #42 — assess converting repo into a distributable Claude Code plugin (5 proposals, ranked) — `/ecc-plan` variant | complete |
| [assess-plugin-packaging-issue-42-native.md](assess-plugin-packaging-issue-42-native.md) | Issue #42 — same assessment, drafted via native Claude Code plan mode (comparison variant) | complete |
| [plugin-packaging-assessment-loop-runbook.md](plugin-packaging-assessment-loop-runbook.md) | Loop runbook (sequential, fast mode) driving `assess-plugin-packaging-issue-42.plan.md` Tasks 1-6 | complete |
