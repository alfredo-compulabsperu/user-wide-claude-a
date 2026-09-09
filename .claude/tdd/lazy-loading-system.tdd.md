# TDD Evidence: lazy-loading-system — Phase 2 (Tasks 2.1, 2.2)

**Source plan:** `.claude/PRPs/plans/lazy-loading-system.plan.md` (Phase 2, run under `/tdd-workflow` per the plan's own note)
**Runner:** pytest 9.0.3 (Python hook; the repo's bash suites under `.claude/tests/` are unaffected)
**Branch:** `worktree-lazy` — every checkpoint below is reachable from `HEAD`

## User journeys

From the plan's User Story: as the operator of a multi-machine Claude Code setup, I want rules to load *whenever their trigger matches* — writes, edits and commands included — before the action lands, at a bounded token cost, so rules are neither silently absent when they apply nor re-billed on every edit.

## Task report

| Task | Summary | Validation command | Result | Checkpoint |
|---|---|---|---|---|
| 2.1 RED | 12 black-box tests + a stub injector that exits 0 emitting nothing | `python3 -m pytest .claude/hooks/tests/ -q` | `12 failed in 0.26s` — 10 on the output contract (no JSON), 2 on must-warn-on-stderr; 0 `ModuleNotFoundError`/`FileNotFoundError` | `4c9ae02` |
| 2.2 GREEN | Real injector replaces the stub; test file untouched (`git diff --stat 4c9ae02 -- tests/…` empty) | same command | `12 passed in 0.53s` | `c4ce66d` |
| 2.2 smoke | Fixture rule with `on:` block, same `Write /tmp/x.ts` payload twice | `echo '{…}' \| python3 .claude/hooks/lazy-rule-inject.py` ×2 | run 1: `{"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": "TS RULE BODY"}}`; run 2: no output, exit 0 | — |
| 2.2 real dirs | Same payload against the live `~/.claude/rules` + `lazy/rules` (51 files) | same | no output, no stderr, exit 0 — expected: no rule carries an `on:` block until Phase 3 | — |

## Test specification

| # | What is guaranteed | Test | Result |
|---|---|---|---|
| 1 | `Write` to a path matching `on.paths` emits the rule body under `hookSpecificOutput.additionalContext` with `hookEventName: PreToolUse` | `test_matching_path_fires_with_rule_body` | PASS |
| 2 | A non-matching path emits nothing (after proving the rule is live) | `test_non_matching_path_is_silent` | PASS |
| 3 | `Bash` command matching `on.commands` fires | `test_command_trigger_fires_for_bash` | PASS |
| 4 | A tool absent from `on.tools` never fires, even on a matching path | `test_tool_not_in_on_tools_is_silent` | PASS |
| 5 | Two rules matching one subject **both** fire (rules don't compete, audit §4-A) | `test_two_rules_matching_same_subject_both_fire` | PASS |
| 6 | Second call, same subject, same session → silent | `test_second_call_same_subject_is_silent` | PASS |
| 7 | Different subject, same session → fires again | `test_different_subject_fires_again` | PASS |
| 8 | Same subject, different session → fires again (dedup is per session) | `test_dedup_is_scoped_per_session` | PASS |
| 9 | Malformed payload → exit 0, no stdout, one stderr line | `test_malformed_payload_exits_zero_and_warns` | PASS |
| 10 | Missing rule dir → exit 0, no stdout, one stderr line | `test_missing_rule_dir_exits_zero_and_warns` | PASS |
| 11 | Malformed frontmatter skips that rule, names it on stderr, other rules still fire | `test_malformed_frontmatter_skips_that_rule_and_continues` | PASS |
| 12 | Empty `file_path` → silent | `test_empty_file_path_is_silent` | PASS |

All tests redirect `LAZY_RULE_INJECT_RULE_DIRS` and `LAZY_RULE_INJECT_MARKER_DIR` to a per-test `tmp_path`, so none touch `~/.claude` or the live session throttle (plan GOTCHA 1).

## Coverage and known gaps

- No line-coverage tool was run (no `coverage`/`kcov` configured in this repo). Qualitatively, every branch in the plan's Testing Strategy table and its Edge Cases checklist is exercised except two, listed below.
- **Not tested — marker dir unwritable → fire anyway + warn.** Implemented (`first_time` catches `OSError`) but a read-only tmpdir fixture was not added this pass.
- **Not tested — concurrent processes on the same subject → exactly one wins.** Relies on `O_CREAT|O_EXCL`, the same primitive `throttle_demo.py` demonstrates; not exercised with real concurrency.
- **Not tested — fork propagation (subagent edit).** Requires a live session; deferred to the plan's Manual Validation at iteration 3.
- **Session-id payload key — verified live at cutover (Task 2.3).** With the hook registered, three `Write` calls from this session: `probe.ts` → all six bodies injected as `PreToolUse` additionalContext *before* the write; `probe.ts` again → nothing; `probe2.ts` → injected again. No "falling back to ppid" line appeared on stderr, so `session_id` is the real key and dedup is per session as designed.
- **Fork propagation and the fresh-session repeat** of the above remain on the plan's Manual Validation list for the user; the in-session run satisfies Task 2.3's VALIDATE line.
- **The plan's real-dir smoke test** became runnable at Task 2.3, when the six lazy bodies gained `on:` blocks; the live run above is that smoke.
- Latency over the real 51 files: see `## Latency` below.

## Latency

10 invocations against the real `~/.claude/rules` + `lazy/rules` (51 files), `Write /tmp/z.ts` payload, measured with `subprocess.run` wall time: **min 27.2 ms, median 29.3 ms, max 31.6 ms**. Dominated by interpreter start-up; the frontmatter scan itself is a small fraction. Re-measure after Phase 3 adds `on:` blocks (bodies then get read and emitted).

## Merge evidence

RED `4c9ae02` → GREEN `c4ce66d`, both on `worktree-lazy`. No refactor commit was needed. If these are squashed, this report is the surviving record of what was verified and how.
