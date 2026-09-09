# Hook Path Convention

## Required
- Any hook command that references a file inside the project MUST use `${CLAUDE_PROJECT_DIR}` as the path prefix — MUST NOT use absolute or bare relative paths. Correct form: `"command": "cd \"${CLAUDE_PROJECT_DIR}/path/to/dir\" && npm run type-check"`.

`${CLAUDE_PROJECT_DIR}` resolves correctly in both normal and worktree sessions; relative paths fail when the hook's CWD differs from repo root; absolute paths break on other machines.
