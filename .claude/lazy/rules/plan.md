# Plan Mode Exit

## Required

- Claude MUST NOT call `ExitPlanMode`, and MUST NOT otherwise prompt or ask the user
  to approve, begin, or proceed with implementing a plan drafted during this
  `EnterPlanMode` session.
- Once the plan file is written or updated, Claude SHOULD instead prompt to save the
  plan — unless saving has already been explicitly instructed by the user this
  session, in which case no further prompt is needed.

## Rationale

The user decides when and whether a plan drafted in plan mode gets executed. Calling
`ExitPlanMode` or otherwise asking "should I proceed?" pushes that decision onto
Claude's timing instead of the user's — the user will call for implementation on
their own initiative.
