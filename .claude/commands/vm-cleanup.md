---
description: Scan and clean dev VM disk consumers (apt, journald, npm, node_modules, worktrees, Trash, snap, nvm)
allowed-tools: Bash
---

Run the cleanup script with any args passed to this command:

```bash
bash "$(git rev-parse --show-toplevel)/.claude/scripts/vm-cleanup.sh" $ARGUMENTS
```

Print the full output verbatim. Do not summarize, truncate, or paraphrase the
script output. When the script exits, add a one-line note if the user should
rerun with `--clean` or `--clean --risky` based on what the output shows. See
`docs/vm-cleanup.md` for the full SAFE/RISKY classification.
