---
description: Report VM resource health, spot issues, and recommend optimizations for dev experience
allowed-tools: Bash
---

Run the health script:

```bash
bash "$(git rev-parse --show-toplevel)/.claude/scripts/vm-health.sh" $ARGUMENTS
```

Print the full output verbatim. Do not summarize or truncate. After the output, add a brief note only if any CRITICAL issues were found.
