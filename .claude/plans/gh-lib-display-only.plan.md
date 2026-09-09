# Plan: Make `open_urls()` Display-Only (No Browser Launch)

**Source PRD**: N/A — ad hoc defect fix from the 2026-09-09 runaway-Chrome incident
**Branch**: `worktree-gh-lib-no-browser` (off `develop`)
**Complexity**: Small

---

## Pre-flight

Human-only items. Everything else in this plan is autonomous.

- [x] **Decide the fate of the surviving orphaned Chrome.** Confirmed 2026-09-09: pid `3570711` no longer exists on the machine. User confirmed via prompt: "already gone."
- [x] **Confirm no other Claude session is mid-run of `.claude/tests/scripts/*.test.sh`.** Confirmed 2026-09-09: no matching test processes found running; user confirmed clear.

If both are already handled, proceed immediately.

---

## Summary

`open_urls()` in `.claude/scripts/gh-lib.sh` prints each URL *and* backgrounds an `xdg-open`/`open` call per URL. Because `xdg-open` routes through `google-chrome.desktop` against the real default profile, every invocation — including every unstubbed test run — relaunches a flagless default-profile Chrome. Three test files exercise this unstubbed. The fix deletes the browser block outright (user's stated requirement: display-only), then adds shim-based test assertions that prove no launcher is ever called again.

---

## Findings that change the brief

| Brief said | Actual state | Consequence |
|---|---|---|
| Tests run via `.claude/tests/run-all.sh` | That file does **not** exist on `develop` or in this worktree. It exists only on branch `worktree-cleanup` (commit `bb113f5`). | The fix lands on `develop`; `worktree-cleanup` inherits it by merge. Local validation uses a `for` loop over `.claude/tests/scripts/*.test.sh`. |
| Two leaking tests (`open-gh-pr`, `open-gh-issue`) | **Three.** `.claude/tests/scripts/gh-lib.test.sh` Test 8 calls `open_urls` directly with `https://example.com/1`, `/2`. | `gh-lib.test.sh` must be in scope. It is the most direct leak. |
| `~/.claude/scripts/gh-lib.sh` is divergent | Confirmed. Live = `f443d94…`, `.sync-state.json` baseline = `59842a3…` = repo's current buggy file. `sync.sh` will report `[DIVERGED]` today. | Convergence is trivial **only if** the repo fix is byte-identical to the live file (see Task 4). |

Verified `diff -u` between repo and live shows exactly the intended change and nothing else.

---

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Test harness | `.claude/tests/scripts/gh-lib.test.sh:12-30` | `run_test(name, pass\|fail)` counters, `bash -n` as Test 1, summary + `exit 1` on failure |
| Mock binaries | `.claude/tests/scripts/open-gh-pr.test.sh:29-37` | Executable heredoc into `mktemp -d`, prepended to `PATH`, `trap 'rm -rf' EXIT` |
| Call-recording shim | `.claude/tests/scripts/open-gh-issue.test.sh:100-104` | Mock writes its args to a sentinel file (`gh.args`) that the test then asserts on — reuse this exact idiom for the `xdg-open` shim |
| Sync semantics | `sync.sh` `install_file` | source==dest → `[OK]` + baseline self-heal, *before* the divergence branch is ever reached |

---

## Decisions (answer these by approving or amending)

### D1 — Rename `open_urls` → `print_urls`? **Recommendation: NO.**

Three concrete costs, zero behavioral gain:

1. **It breaks the free convergence.** The hand-patched live file keeps the name `open_urls`. Keeping the name makes the repo file byte-identical to `~/.claude/scripts/gh-lib.sh`, so `sync.sh` hits the `[OK]` branch and self-heals the baseline with no prompt. A rename makes them differ → `[DIVERGED]` → an interactive prompt or `--force-diverged`, for cosmetics.
2. **Merge blast radius.** Nine worktree branches carry their own checkout of `gh-lib.sh`, both callers, and the tests. A one-hunk deletion merges cleanly everywhere; a rename touching 5 files does not.
3. **YAGNI.** `open_urls` reads fine as "open these URLs (for the user, in their terminal)". The updated comment states the contract explicitly. A misnomer that costs nothing to keep is not worth a cross-branch rename.

### D2 — Keep a `NO_BROWSER_OPEN` / `CLAUDE_TEST_MODE` guard? **Recommendation: NO.**

A guard exists to conditionally suppress a call. After this fix there is no call to suppress — the guard would be a branch that can never do anything, i.e. pure dead weight, and it would falsely imply a browser path still exists somewhere. Defense-in-depth belongs in the **tests**, not in production code: Task 3 adds a shim that fails the suite if any launcher is ever invoked. That catches a regression at the exact moment someone reintroduces one, which an env-var guard would not.

### D3 — Test surface expansion. **Explicit scope decision, approved as part of this plan.**

Per the standing rule this is surfaced here rather than done silently. The plan adds **4 new assertions** and modifies **3 existing test files** (details in Tasks 2–3). Approving this plan approves those test changes; no second confirmation is needed at implementation time.

---

## Files to Change

| File | Action | Why |
|---|---|---|
| `.claude/scripts/gh-lib.sh` | UPDATE | Delete the `xdg-open`/`open` block; rewrite the function comment |
| `.claude/tests/scripts/gh-lib.test.sh` | UPDATE | Install launcher shims; add "open_urls never invokes a browser launcher" assertion |
| `.claude/tests/scripts/open-gh-pr.test.sh` | UPDATE | Install launcher shims; add no-launch assertion |
| `.claude/tests/scripts/open-gh-issue.test.sh` | UPDATE | Install launcher shims; add no-launch assertion |
| `.claude/scripts/open-gh-pr.sh` | **no change** | Caller contract unchanged (D1) |
| `.claude/scripts/open-gh-issue.sh` | **no change** | Same |
| `.claude/commands/open-gh-*.md` | **no change** | Frontmatter already says "Output … URLs by ID(s)" — docs were already correct |
| `manifest.yaml` | **no change** | `gh-lib.sh` already listed under `scripts:` |

---

## Tasks

> **Step-ordering constraint (hard):** Task 1 and Task 3 MUST both be complete before *any* test file is executed. Running the suite in its current state reproduces the incident and spawns real Chrome tabs. No pre-fix "confirm the failure" run.

### Task 1: Fix `open_urls()` — do this first

- **Action**: Replace the function and its comment with exactly:
  ```bash
  # open_urls: print each URL to stdout. Display-only by design — never launches a browser.
  open_urls() {
    local urls=("$@")
    for url in "${urls[@]}"; do echo "$url"; done
  }
  ```
- **Critical**: must be **byte-identical** to `~/.claude/scripts/gh-lib.sh`. Verify with `diff` before proceeding (Task 4 depends on it).
- **Validate**: `bash -n .claude/scripts/gh-lib.sh` and `diff .claude/scripts/gh-lib.sh ~/.claude/scripts/gh-lib.sh` → empty.

### Task 2: Neutralize the launchers in all three test files

- **Action**: In each of `gh-lib.test.sh`, `open-gh-pr.test.sh`, `open-gh-issue.test.sh`, immediately after `MOCK_BIN="$(mktemp -d)"`, write executable `xdg-open` and `open` shims into `$MOCK_BIN`. Each shim appends its args to `$MOCK_BIN/launcher.calls` and exits 0 — it never execs anything.
- **Note**: `gh-lib.test.sh` currently runs its `open_urls` case *without* `PATH="$MOCK_BIN:$PATH"` (line 154). That invocation must be changed to prepend `$MOCK_BIN`, or the shim is bypassed and the test still leaks.
- **Mirror**: the `gh.args` recording idiom from `open-gh-issue.test.sh:100-104`.
- **Validate**: covered by Task 3's assertion.

### Task 3: Add the no-launch assertions

- **Action**: Add one new test at the end of each of the three files: `[[ ! -f "$MOCK_BIN/launcher.calls" ]]` → pass, else fail and print the recorded calls. In `gh-lib.test.sh`, keep the existing Test 8 stdout assertion (the contract it checks is unchanged and still correct) and add the no-launch check as Test 9.
- **Why this and not an env guard**: this fails loudly the moment anyone reintroduces a launcher call anywhere under `open_urls`, including via a future caller.
- **Validate**: run the suite (now safe):
  ```bash
  for t in .claude/tests/scripts/*.test.sh; do bash "$t" || echo "FAILED: $t"; done
  ```

### Task 4: Re-converge the synced copy

- **Action**: After Task 1, run `bash sync.sh --dry-run` and confirm `scripts/gh-lib.sh` reports `[OK]`, **not** `[DIVERGED]`. Then run `bash sync.sh` (no flags).
- **Expected mechanics** (read from `sync.sh` `install_file`): source hash now equals dest hash → the `[OK]` branch fires *before* the three-way divergence check is reached, and `sync_state_set` self-heals the `.sync-state.json` baseline from `59842a3…` to `f443d94…`. No prompt, no `--force`, no `--force-diverged`, no conflict.
- **If it reports `[DIVERGED]` instead**: Task 1 was not byte-identical. Fix the repo file to match rather than forcing the overwrite.
- **Scope guard**: `~/.claude/` is never hand-edited by this plan. `sync.sh` is the only thing that writes there.

### Task 5: Verify no browser launches

- **Action**, in order:
  1. `grep -rn 'xdg-open\|disown' .claude/scripts/` → expect zero hits.
  2. Record `pgrep -fc '/opt/google/chrome/chrome'` (or `0` if none).
  3. Run the full suite (Task 3 command).
  4. Re-check `pgrep -fc '/opt/google/chrome/chrome'` → must be unchanged.
  5. Confirm every test file reported its no-launch assertion as PASS.
- **Note**: step 4 is the end-to-end proof; step 5 is the durable regression guard that survives into CI and future edits.

### Task 6: Land once, propagate by merge

- **Action**: Commit on `worktree-gh-lib-no-browser`, open a PR targeting **`develop`** (per the PR-base rule), merge.
- **Propagation**: the nine sibling worktree branches (`cleanup`, `mcp-ops`, `gh`, `git-ops`, `synthetic-doodling-boot`, `lazy`, `ship-skill-plan`, `claude-plugin-packaging`) are branches of one repo — each picks the fix up on its next `git merge develop`. **Do not hand-patch nine checkouts.**
- **Call out to the user**: `worktree-cleanup` is the branch that owns `.claude/tests/run-all.sh` and is where the 11 incident-causing runs originated. It MUST merge `develop` before its suite is run again, or it keeps reproducing the bug locally. This is the one branch worth flagging explicitly rather than leaving to routine merge.

---

## Validation

```bash
bash -n .claude/scripts/gh-lib.sh
diff .claude/scripts/gh-lib.sh ~/.claude/scripts/gh-lib.sh          # must be empty
grep -rn 'xdg-open\|disown' .claude/scripts/                        # must be empty
pgrep -fc '/opt/google/chrome/chrome' || true                       # record before
for t in .claude/tests/scripts/*.test.sh; do bash "$t" || echo "FAILED: $t"; done
pgrep -fc '/opt/google/chrome/chrome' || true                       # must be unchanged
bash sync.sh --dry-run                                              # scripts/gh-lib.sh → [OK]
bash sync.sh
```

---

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Suite is run before Task 1+3 complete, spawning Chrome again | Medium — it is the reflexive move | Hard step-ordering constraint stated above; no pre-fix "confirm failure" run in this plan |
| Repo fix not byte-identical → `[DIVERGED]` prompt on sync | Low | Explicit `diff` gate in Task 1; Task 4 says fix the file, never `--force-diverged` |
| `gh-lib.test.sh` Test 8 keeps leaking because its `open_urls` call omits `PATH="$MOCK_BIN:$PATH"` | Medium — easy to miss | Called out explicitly in Task 2; the Task 3 assertion would not catch a shim that was never on `PATH`, so this is a manual read-check |
| A sibling worktree runs its stale suite before merging `develop` | Medium | Task 6 flags `worktree-cleanup` by name to the user |
| Someone reintroduces a launcher call later | Low | Task 3's shim assertion fails the suite immediately |
| Killing pid 3570711 destroys the user's live browser state | N/A — deliberately not Claude's call | Pre-flight item, human decision |

---

## Acceptance

- [x] `open_urls()` contains only the print loop; no `xdg-open`, `open`, or `disown` anywhere in `.claude/scripts/`
- [x] Repo `gh-lib.sh` is byte-identical to `~/.claude/scripts/gh-lib.sh`
- [x] All three test files install launcher shims and assert they were never called
- [x] Full suite passes with no new `/opt/google/chrome/chrome` process
- [x] `sync.sh --dry-run` reports `[OK]` for `scripts/gh-lib.sh`; `sync.sh` re-baselines `.sync-state.json` without a prompt
- [x] No rename (D1), no env-var guard (D2) — unless amended at approval
- [ ] Merged to `develop` via PR; `worktree-cleanup` flagged to merge before its next test run — **PR #64 opened**, targeting `develop`, not yet merged (holding for user go-ahead)
