---
paths:
  - ".claude/plans/**/*.md"
  - "docs/**/*.md"
on:
  tools: [Edit, Write]
  paths: [".claude/plans/**/*.md", "docs/**/*.md"]
---
# Two-Pass Artifact Verification

## Required

Pass B MUST run without the drafting context. An in-context re-read only re-checks what the author thought to check; isolation catches unchecked interfaces, unsourced recalls, and salience omissions — the classes a diligent first pass structurally misses.

## Recommended

Substantive artifacts — plans, runbooks, recommendation docs, research syntheses, knowledge extractions, retrospectives — SHOULD be produced in two passes: Pass A drafts; Pass B is an isolated fresh-context agent given the same input, verifying every claim against the sources and rewriting or reporting corrections freely.

Mechanics are owned by the `fact-grounded-authoring` skill (renamed from `plan-fact-grounding` 2026-08-19; verify interfaces on disk, dry-run validation commands, isolated pass as *primary author* for extractions/retrospectives, blind-twin escalation for high-value artifacts). This rule sets the default scope; that skill owns the how — do not duplicate its text here.

If the user's request contains a single-pass marker — `1pass`, `1 pass`, `one pass`, `onepass`, `single pass`, `singlepass` (case-insensitive) — run Pass A only, no Pass B, no confirmation prompt. Example: `/ecc:plan "..." 1pass`. The marker overrides the two-pass default for that artifact only, not for the session.

Adopted 2026-08-18: an isolated Pass B found 8 corrections in a plan whose Pass A *had* verified 21 claims on disk — 2 execution-blocking, 2 methodology-invalidating — at ~2% of session cost. Requested by the user for four consecutive artifact types in one session.

## Advisory

Pass B MAY be skipped for throwaway artifacts, or artifacts making no concrete interface/fact claims (nothing to verify).
