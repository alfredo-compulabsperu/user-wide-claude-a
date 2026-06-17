---
description: Rename the current tmux window; defaults to branch/worktree name when no argument given
model: claude-haiku-4-5-20251001
---

Extract the window name from `$ARGUMENTS` (the first non-flag token).

If a name was given, run:

```
bash "$HOME/.claude/scripts/rename-tmux-window.sh" "<name>"
```

If no name was given, run without arguments (the script will compute a default from the current branch/worktree):

```
bash "$HOME/.claude/scripts/rename-tmux-window.sh"
```

Do not output anything after the tool call — the tool result already surfaces the output.
