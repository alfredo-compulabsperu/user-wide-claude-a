# Hooks

| Rule | Requirement |
|---|---|
| Script location | Hook command scripts (registered under `hooks.<Event>` in `settings.json`/`settings.local.json`) MUST live in `.claude/hooks/`. |
| Distinction from command scripts | `.claude/scripts/` MUST remain reserved for scripts that `.claude/commands/*.md` slash commands depend on (per the Command Scripts rule). Hook scripts are a separate category and MUST NOT be placed there. |
| Reference form | Hooks MUST invoke them as `${CLAUDE_PROJECT_DIR}/.claude/hooks/<name>.sh`, per the Hook Path Convention rule. |
| File extension | Hook script files MUST use the `.sh` extension. |
| Rationale | Anthropic's own Claude Code hooks documentation (`docs.claude.com/en/docs/claude-code/hooks`) conventionally places hook scripts under `.claude/hooks/`; this rule adopts that convention so hook scripts stay distinguishable from command-dependency scripts. |
