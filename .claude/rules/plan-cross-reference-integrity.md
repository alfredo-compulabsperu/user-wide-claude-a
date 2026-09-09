---
paths:
  - ".claude/plans/**/*.md"
on:
  tools: [Edit, Write]
  paths: [".claude/plans/**/*.md"]
---

# Plan Cross-Reference Integrity

When adding a new task or step to an existing numbered plan, it MUST be inserted at the position its dependencies require — after what it depends on, before what depends on it. It MUST NOT be appended at the end merely because that avoids renumbering.

After adding, removing, or reordering numbered tasks or steps, the full plan file MUST be grepped for every old and new task label (e.g. `T9`, `Task 9`) before the edit is treated as done. Positional references recur in multiple sections — cross-reference tables, validation scripts, risk tables, acceptance checklists — and go stale silently on renumber.

If the plan states a task or step count in prose (e.g. "10 tasks"), that count MUST be reconciled against the actual number of task/step headers whenever a task is added or removed.

This was observed directly in `create-resume-2-hardening.plan.md`: a task was appended after the plan's final gate step even though that gate step already referenced the new task's output, breaking the plan's own stated execution order. A first fix pass corrected four of five scattered references and missed one, caught only by a follow-up grep — the sweep above is meant to catch it the first time.
