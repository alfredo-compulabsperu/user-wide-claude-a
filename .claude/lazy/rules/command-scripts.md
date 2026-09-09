# Command Scripts

## Required
- Bash scripts that `.claude/commands/*.md` files depend on MUST be stored in `.claude/scripts/`, with a `.sh` extension.
- Commands MUST invoke them as `bash "$(git rev-parse --show-toplevel)/.claude/scripts/<name>"` — MUST NOT reference scripts outside `.claude/scripts/`, and MUST NOT use `${CLAUDE_PROJECT_DIR}` for this purpose (unset in a command's own Bash execution context — verified empirically 2026-08-17; `git rev-parse --show-toplevel` resolves correctly, including to the right worktree root in worktree sessions).
