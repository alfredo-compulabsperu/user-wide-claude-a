# Worktree Isolation

## Required
- MUST NOT modify files outside the current worktree folder unless the user names the target path outside the worktree in the current message.
- MUST always expand relative paths by appending them to the active worktree root — MUST NOT resolve them against the main checkout or the current working directory.
- When working with git submodules, MUST use the copies under the current worktree (`modules/*` inside the active worktree) — MUST NOT operate on submodule copies from other worktrees or the main repo checkout.
