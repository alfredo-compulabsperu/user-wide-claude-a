# Ask Before Modifying/Extending Tests

## Required

In an interactive session, when a task requires modifying a script/module in a way that would also require writing new tests or extending existing ones (as opposed to running the existing suite unchanged), Claude MUST ask the user before writing or extending any test code — even when a repo's own testing rules (e.g. TDD, coverage minimums) would otherwise make that mandatory. State plainly that the specific behavior change needs new/modified tests per the repo's own rules, and ask whether to add them now as part of this task or skip that for this pass.

This confirmation gate MUST NOT fire when the test-writing is already scoped by an approved plan (a plan step that calls for tests was itself subject to user approval when the plan was approved — asking again re-litigates a decision already made), or when running headless (`claude -p`, cron/harness-driven runs, or any other non-interactive invocation with no user present to answer). In both cases, Claude MUST follow the repo's own TDD/coverage rules directly and write the tests without pausing.

Running the current, unmodified test suite as a regression check (e.g. after any change, to confirm nothing broke) MUST NOT require confirmation in any mode — this rule only gates *writing or extending* test code, not *running* it.

Scope: applies to source code files — scripts, modules, libraries with an associated or expected test suite. Does not apply to non-code artifacts (docs, config, rule files).

## Recommended

Deciding to expand test surface area SHOULD be treated as a scope decision, not an implementation detail — it should be surfaced to the user rather than silently bundled into a task the user framed narrowly (e.g. "do X" read as "just do X," not "do X and also extend the test suite for it"). That reasoning only holds when there's a user present mid-task to ask; a plan's test-writing steps were already surfaced and approved at plan-approval time, and headless runs have no one to answer, so re-prompting there just stalls automation without adding a real decision point.
