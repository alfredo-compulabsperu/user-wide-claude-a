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
| [token-optimizer.plan.md](token-optimizer.plan.md) | Two Claude commands that reduce per-turn token cost by disabling unused tools | draft |
