# Plan: vm-cleanup.sh worktree fixes + promotion (issue #36)

**Source**: GitHub issue #36 — vm-cleanup.sh: worktree protected-branch leaves husks, depth-mismatched protection scan, script untracked
**Complexity**: Small–Medium (~1–2 h, mostly the sandbox test)

## Pre-flight

- [x] None — no human-only tasks identified. No credentials, UI actions, or external-system changes are needed (no `sudo` is involved in the fixes or their validation; git push and PR creation are autonomous).

## Summary

Land three fixes to `~/.claude/scripts/vm-cleanup.sh` as a tracked change in this repo:

1. **Fix 1 — no more husks**: when a clean/pushed/unlocked worktree contains protected files (`.env*`, `*.pem`, etc.), stop doing `find -delete` + no-op `prune` (which leaves a registered worktree showing ~100% deletions). Instead move protected files to a rescue dir `~/.claude/cleanup-rescue/<wt-name>-<date>/`, print that location, then `git worktree remove --force` so the worktree is unregistered.
2. **Fix 2 — depth mismatch**: `_has_protected` probes with `-maxdepth 5` while the destructive paths have no depth limit → a protected file at depth 6+ gets deleted wholesale. Drop the `-maxdepth 5` (the probe is `-print -quit`; cost trivial). Bonus: current placement of `-maxdepth` after the expression triggers a GNU find warning — dropping it also removes that.
3. **Fix 3 — track the script**: add `vm-cleanup.sh` to this repo's `.claude/scripts/` + `manifest.yaml`, then sync so the VM copy is byte-identical to the repo and future changes are diffable.

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Script style | `~/.claude/scripts/vm-cleanup.sh:46-74` | Helper functions `_safe`/`_confirm`/`_skip` take a description + command argv; `_confirm` runs `"$@"` — so Fix 1 can be a **shell function** passed to `_confirm`, replacing the current inline `bash -c` blob |
| DRY | `vm-cleanup.sh:69-73` vs `:243-245` | The protected-name predicate list is duplicated in `_has_protected` and the deleting `find`. Two callsites → extract to a shared array `PROTECTED_EXPR=( -name '.env' -o ... )` used by both |
| Manifest entry | `manifest.yaml:29-38` | Scripts listed as `- name: <file>.sh` with `executable: true` when invoked directly |
| Repo script home | `.claude/scripts/` (7 existing `.sh` files) | Per Command Scripts rule; `sync.sh:519` installs from `.claude/scripts/<name>` → `~/.claude/scripts/<name>` |
| Tests | — | No test framework exists in this repo. Validation is `bash -n`, `shellcheck` (if present), plus a sandboxed functional run (Task 4). No pattern invented. |

## Files to Change

| File | Action | Why |
|---|---|---|
| `.claude/scripts/vm-cleanup.sh` | CREATE | Hardened VM version + Fixes 1–2 applied |
| `manifest.yaml` | UPDATE | Add `- name: vm-cleanup.sh` / `executable: true` under `scripts:` |
| `~/.claude/scripts/vm-cleanup.sh` | UPDATE (via `sync.sh`) | VM copy synced from repo; sync-state records SHA |

Note: the local `~/.claude/commands/vm-cleanup.md` command that invokes the script is **also untracked**, but it's outside issue #36's scope — leave it and mention it as a possible follow-up issue.

## Tasks

### Task 1 — Import script into repo
- **Action**: Copy current `~/.claude/scripts/vm-cleanup.sh` to `.claude/scripts/vm-cleanup.sh` unchanged, commit as its own commit ("import as-is") so Fixes 1–2 are a reviewable diff on top.
- **Validate**: `git show --stat HEAD` shows only the new file; `diff ~/.claude/scripts/vm-cleanup.sh .claude/scripts/vm-cleanup.sh` is empty.

### Task 2 — Fix 2: shared protected predicate, no depth cap
- **Action**: Extract `PROTECTED_EXPR` array; `_has_protected` becomes `find "$1" \( "${PROTECTED_EXPR[@]}" \) -print -quit` (no `-maxdepth`).
- **Mirror**: DRY extraction at two callsites.
- **Validate**: `bash -n`; sandbox test with protected file at depth 6 routes to protected branch.

### Task 3 — Fix 1: rescue + remove, no husk
- **Action**: New function `_rescue_and_remove_worktree <wt> <repo>`:
  - Rescue dir: `~/.claude/cleanup-rescue/$(basename wt)-$(date +%Y%m%d-%H%M%S)`
  - `find "$wt" \( "${PROTECTED_EXPR[@]}" \) -print0` → move each match preserving its worktree-relative path
  - Print rescue location, then `git -C "$repo" worktree remove --force "$wt"` (force is required and safe: eligibility gates — unlocked, clean, pushed, not self — already passed)
  - Protected branch calls `_confirm "rescue protected files + git worktree remove: $wt" _rescue_and_remove_worktree "$wt" "$repo"`
- **Mirror**: `_confirm` argv-function pattern.
- **Validate**: sandbox test asserts worktree unregistered + rescue dir populated + path printed.

### Task 4 — Sandboxed functional validation
- **Action**: `bash -n` + `shellcheck` (if installed). Build a throwaway `HOME` in the scratchpad with a stub-`PATH` (no-op `sudo`/`apt-get`/`journalctl`/`npm`/`snap`) containing a test repo + worktree that is clean, pushed (file:// remote), unlocked, with a protected file at **depth 6**. Run `HOME=<sandbox> ... --clean --yes` and assert: worktree gone from `git worktree list`, deep protected file present in rescue dir, rescue path printed. Also assert a locked/dirty worktree is still skipped.
- **Validate**: all assertions pass; this exercises every acceptance-criteria bullet for Fixes 1–2.

### Task 5 — Manifest + sync
- **Action**: Add manifest entry; run `bash sync.sh --dry-run` then `bash sync.sh --force` (VM copy predates repo copy, so SHA will mismatch — force is the intended path; sync-state self-heals).
- **Validate**: `sha256sum .claude/scripts/vm-cleanup.sh ~/.claude/scripts/vm-cleanup.sh` match.

### Task 6 — Ship
- **Action**: Branch off this worktree's branch, commits per task, push, PR → `develop` with `Closes #36`. Stops at the PR; merge on user's call.
- **Validate**: PR open against `develop`, CI (if any) green.

## Validation

```bash
bash -n .claude/scripts/vm-cleanup.sh
shellcheck .claude/scripts/vm-cleanup.sh   # if available
# sandbox functional test (Task 4 script, in scratchpad)
bash sync.sh --dry-run && bash sync.sh --force
sha256sum .claude/scripts/vm-cleanup.sh ~/.claude/scripts/vm-cleanup.sh
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| `git worktree remove --force` is destructive if eligibility gates regress | Low | Gates untouched by this change; sandbox test asserts a locked/dirty worktree is still skipped |
| `mv` across filesystems for rescue (worktree on different mount than `~`) | Low | Single-disk VM; `mv` falls back to copy+unlink anyway |
| `sync.sh --force` overwrites some *other* locally-diverged artifact | Low | `--dry-run` first; force only after reviewing its report |
| Protected *directories* (e.g. `*secret*` dir) match `-name` but rescue loop assumes files | Medium | Rescue find uses the predicates without `-type f`, moving matched dirs wholesale (mirrors current delete semantics) — finalize during implementation |

## Acceptance

- [ ] Cleaning a worktree with protected files ends with the worktree unregistered (`git worktree list` no longer shows it) and protected files preserved in a rescue location printed in the output
- [ ] A protected file at any depth routes the worktree to the protected branch
- [ ] `vm-cleanup.sh` tracked in this repo; VM copy synced from it (SHA match)
- [ ] All tasks complete, validation passes, patterns mirrored
