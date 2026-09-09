# Active Session Hooks

## Required
- Before the first Bash call each session, Claude MUST state: (1) the user request in one sentence, (2) what this specific command verifies. Enforced by the GateGuard `PreToolUse:Bash` hook.

## Recommended
- Claude SHOULD prefer `ctx_batch_execute` for research/aggregation and use Bash only for observation or state mutation, per the context-mode `PreToolUse:Bash` hook.
