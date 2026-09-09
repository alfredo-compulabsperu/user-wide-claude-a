---
paths:
  - "**/settings.json"
  - "**/settings.local.json"
on:
  tools: [Edit, Write]
  paths: ["**/settings.json", "**/settings.local.json"]
---
# Hooks

| Rule | Requirement |
|---|---|
| Script location | Hook command scripts (registered under `hooks.<Event>` in `settings.json`/`settings.local.json`) MUST live in `.claude/hooks/`. |
| Distinction from command scripts | `.claude/scripts/` MUST remain reserved for scripts that `.claude/commands/*.md` slash commands depend on (per the Command Scripts rule). Hook scripts are a separate category and MUST NOT be placed there. |
| Reference form | Hooks MUST invoke them as `${CLAUDE_PROJECT_DIR}/.claude/hooks/<name>.sh`, per the Hook Path Convention rule. |
| File extension | Hook script files MUST use the `.sh` extension. |
| Rationale | Anthropic's own Claude Code hooks documentation (`docs.claude.com/en/docs/claude-code/hooks`) conventionally places hook scripts under `.claude/hooks/`; this rule adopts that convention so hook scripts stay distinguishable from command-dependency scripts. |

## Hook Path Convention

## Required
- Any hook command that references a file inside the project MUST use `${CLAUDE_PROJECT_DIR}` as the path prefix — MUST NOT use absolute or bare relative paths. Correct form: `"command": "cd \"${CLAUDE_PROJECT_DIR}/path/to/dir\" && npm run type-check"`.

`${CLAUDE_PROJECT_DIR}` resolves correctly in both normal and worktree sessions; relative paths fail when the hook's CWD differs from repo root; absolute paths break on other machines.
