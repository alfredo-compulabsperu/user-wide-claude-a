# User-Wide Claude Artifact Portability

## Problem

A solo developer working across up to 4 machines must manually copy user-wide Claude artifacts whenever a new machine is set up or when artifacts evolve. There is no source of truth, no backup, and no way to know whether a machine is current, missing artifacts, or has local-only work worth promoting.

## Evidence

- Up to 4 active machines require the same Claude setup
- Developer has experienced re-setup effort after machine changes
- Affected artifact types confirmed via audit: skills, commands, agents, scripts, CLAUDE.md, user-scope plugins

## Users

- **Primary**: Solo developer managing Claude Code across multiple Linux machines
- **Not for**: Teams, project-level `.claude/` sync, other users' environments

## User Stories

| As a… | I want to… | So that… |
|---|---|---|
| User | Install all user-wide artifacts on a new machine with a single bash script | I reach full parity immediately without manual steps |
| User | Detect local user-wide artifacts not in the repo and promote them with one command | My curated setup is never lost and travels with me |
| Harness | Automatically branch, push, open a PR, review, fix, and merge any newly promoted artifact | Promoted artifacts are validated and version-controlled without human pipeline overhead |

## Hypothesis

We believe a **git-backed artifact sync system with a manifest** will **eliminate manual re-setup effort** for a solo developer across up to 4 machines.
We'll know we're right when **a fresh machine reaches full user-wide Claude artifact parity in under 5 minutes with zero manual file copying**.

## Success Metrics

| Metric | Target | How measured |
|---|---|---|
| Time to full parity on fresh machine | < 5 min | Manual timing of install run |
| Manual file copy steps required | 0 | Run checklist post-install |
| Machines out of sync detected | On demand | Manifest diff check command |

## Scope

**Portable artifact types** (confirmed via audit 2026-06-09):

| Artifact | Path under `~/.claude/` |
|---|---|
| Skills | `skills/` |
| Commands | `commands/` |
| Agents | `agents/` |
| Scripts | `scripts/` |
| User-wide CLAUDE.md | `CLAUDE.md` |
| User-scope plugins | declared in a repo manifest; reinstalled on target |

**Excluded artifact types** (machine-local or secret state — not portable):

| Artifact | Reason excluded |
|---|---|
| `settings.json` | May contain API keys, auth tokens, machine-specific paths |
| `.credentials.json` | Secrets — never in source control |
| `sessions/`, `history.jsonl` | Machine-local runtime state |
| `cache/`, `jobs/`, `tasks/` | Ephemeral runtime state |
| `plugins/cache/`, `plugins/data/`, `plugins/config/` | Machine-local derived plugin state |
| Project-scoped plugins | Travel with their projects, not this repo |

**MVP**:
- This repo is the single source of truth for all user-wide Claude artifacts
- A new machine reaches full artifact parity by running one command
- A machine can report whether it is current, missing artifacts, or has local-only changes worth promoting

**Out of scope**
- Project-level `.claude/` sync — each project manages its own
- `settings.json` sync — too risky (secrets, machine-specific)
- Auto-review or auto-fix of promoted artifacts — validation gate is sufficient
- Auto-deploy on machine boot or file-watch
- Team or multi-user sharing
- OS portability beyond Linux
- Conflict resolution beyond detection — human decides

## Delivery Milestones

| # | Milestone | Outcome | Status | Plan |
|---|---|---|---|---|
| 1 | Artifact audit | Canonical portable and excluded artifact types confirmed | complete | — |
| 2 | Manifest format | Manifest schema defined and populated with current artifact set | complete | `.claude/plans/plan-m2-manifest.plan.md` |
| 3 | Sync script | A new machine reaches full artifact parity by running one command; `--dry-run` flag reports missing/stale/local-only artifacts without applying changes | complete | `.claude/plans/plan-m3-sync-script.plan.md` |
| 4 | `/validate-artifact` skill | An artifact can be validated as repo-agnostic, dependency-complete, and terse — standalone, callable independently of promote | complete | `.claude/plans/plan-m4-validate-artifact.plan.md` |
| 5 | `/promote-artifact` skill (local) | An artifact passes validation then is copied to `~/.claude/<type>/` — works offline, no git required | complete | `.claude/plans/plan-m5-promote-local.plan.md` |
| 6 | `/promote-artifact` git pipeline | Promoted artifact is branched, committed, pushed, PR created, and squash-merged automatically — no auto-review, no auto-fix | complete | `.claude/plans/plan-m6-promote-git.plan.md` |

## Open Questions

- [ ] Should the manifest be a flat file (JSON/YAML) or inferred from directory structure?
- [ ] What is the idempotency behavior — overwrite silently, skip if exists, or prompt?
- [ ] Is `CLAUDE.md` fully portable or does it contain any machine-specific content?
- [ ] How does `/validate-artifact` detect repo-agnostic violations — static grep for known path patterns, or LLM judgment?
- [ ] Merge strategy for the git pipeline — squash resolved (council), but what is the PR title/body convention?

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Accidentally syncing secrets via `settings.json` | Medium | High | Explicit exclusion list; never track `settings.json` |
| Overwriting local customizations on target machine | Medium | Medium | Local-only detection before overwrite |
| Repo drifts from actual `~/.claude/` state | High | Low | Drift detection script run periodically |

---
*Status: DRAFT — requirements only. Implementation planning pending via /plan.*
