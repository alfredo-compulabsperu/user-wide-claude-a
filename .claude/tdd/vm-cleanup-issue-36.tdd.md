# TDD Evidence Report — vm-cleanup.sh worktree fixes (issue #36)

## Source plan

`.claude/plans/vm-cleanup-issue-36.plan.md` (GitHub issue #36). User journeys and
acceptance criteria were taken from the plan; none were invented during this run.

## User journeys

1. As a VM operator, I want cleaning a clean/pushed worktree that contains protected
   files to fully unregister the worktree while preserving those files in a printed
   rescue location, so cleanup reclaims the space without leaving husks or losing secrets.
2. As a VM operator, I want a protected file at **any** depth to route the worktree to
   the protected-handling branch, so no secret is deleted because it sits deeper than
   an arbitrary scan cap.
3. As a repo maintainer, I want `vm-cleanup.sh` tracked in this repo and synced to the
   VM, so future changes are diffable and reviewable.

## Task report

| Plan task | Summary | Validation run | Result |
|---|---|---|---|
| 1 Import | Copied `~/.claude/scripts/vm-cleanup.sh` into repo unchanged | `diff` empty; `git show --stat baa2ab4` = 1 new file | done |
| 4 Test (written first) | Sandbox reproducer `.claude/tdd/test-vm-cleanup-issue-36.sh` | RED run against baseline | 5 FAIL / 4 PASS (see below) |
| 2+3 Fixes | `PROTECTED_EXPR` extraction, depth cap dropped, rescue+remove function | `bash -n` OK; GREEN rerun of same test | 9/9 PASS |
| 5 Manifest+sync | Manifest entry added; `sync.sh --dry-run` reviewed (diverged: 0), then `--force` | `sha256sum` repo copy vs `~/.claude` copy | identical (`063991d7…`) |

### RED evidence (baseline, commit `baa2ab4`; test commit `f096c96`)

```
PASS: script exits 0
FAIL: wt-shallow unregistered (no husk)
PASS: wt-deep unregistered
FAIL: shallow .env rescued
FAIL: depth-6 .env rescued preserving relative path
FAIL: rescue location printed
FAIL: depth-6 file routes wt-deep to protected branch
PASS: locked worktree untouched
PASS: dirty worktree untouched
RESULT: RED
```

Run log confirmed the failures are the intended bugs: `wt-deep` took the plain
`git worktree remove` branch (depth-6 `.env` missed by the `-maxdepth 5` probe) and
`wt-shallow` took the delete+prune branch that leaves a registered husk.

### GREEN evidence (fix commit `e42c5c8`)

Same test target rerun unchanged: all 9 assertions PASS, `RESULT: GREEN`, exit 0.

## Test specification

| # | What is guaranteed | Assertion in `.claude/tdd/test-vm-cleanup-issue-36.sh` | Type | Result |
|---|---|---|---|---|
| 1 | Script exits 0 under `--clean --yes` in the sandbox | `script exits 0` | functional | PASS |
| 2 | Worktree with shallow protected file ends unregistered (no husk) | `wt-shallow unregistered` | functional | PASS |
| 3 | Worktree with depth-6 protected file ends unregistered | `wt-deep unregistered` | functional | PASS |
| 4 | Shallow `.env` preserved in rescue dir | `shallow .env rescued` | functional | PASS |
| 5 | Depth-6 `.env` preserved with worktree-relative path | `depth-6 .env rescued preserving relative path` | functional | PASS |
| 6 | Rescue location printed in output | `rescue location printed` | functional | PASS |
| 7 | Depth-6 protected file routes to the protected branch | `depth-6 file routes wt-deep to protected branch` | functional | PASS |
| 8 | Locked worktree still skipped (gate regression) | `locked worktree untouched` | functional | PASS |
| 9 | Dirty worktree still skipped (gate regression) | `dirty worktree untouched` | functional | PASS |

Reproduce: `bash .claude/tdd/test-vm-cleanup-issue-36.sh .claude/scripts/vm-cleanup.sh <sandbox-dir>`
(throwaway `HOME`, stubbed `sudo`/`apt-get`/`journalctl`/`npm`/`snap`, bare-file remote).

## Coverage and known gaps

- No coverage tooling exists for bash in this repo (plan: "No test framework exists…
  No pattern invented"); the sandbox test exercises every acceptance-criteria bullet
  of issue #36 Fixes 1–2. `shellcheck` not installed on this VM — `bash -n` only.
- Not exercised: protected *directory* matches (risk table item; rescue `find` uses
  `-prune` so a matched dir moves wholesale, mirroring prior delete semantics),
  cross-filesystem `mv`, and the apt/journald/snap/npm sections (stubbed no-ops).
- Pre-existing, unrelated: `sync.sh` plugin step fails for `ecc@ecc` with
  `unknown option '--marketplace'` (present before this change).

## Merge evidence (for squash)

RED `f096c96` (5 FAIL on baseline for the two intended bugs) → GREEN `e42c5c8`
(9/9 PASS, same test unchanged) → no separate refactor commit (DRY extraction of
`PROTECTED_EXPR` was itself part of the minimal fix) → manifest+sync `6406569`
(repo↔VM sha256 identical).

Pre-merge review hardening: a failed `mkdir`/`mv` during rescue now aborts before
`git worktree remove --force` (set -e is suppressed inside `_confirm`'s `|| true`
pipeline, so the guard must be explicit), and the rescue `find` gained `-mindepth 1`
so a worktree directory itself named like a protected pattern (e.g. `*secret*`)
can't be moved wholesale. Sandbox test rerun after hardening: 9/9 PASS. The
rescue-failure abort path itself is untested (simulating `mv` failure needs a
second sandbox scenario — deferred).
