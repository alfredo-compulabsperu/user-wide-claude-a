---
on:
  tools: [Bash]
  commands: ["gh pr create*", "gh pr edit*"]
---
# PR Base Branch

## Required
- All PRs MUST target `develop` — MUST NOT target `main` or `master`. `main` advances only by promoting `develop` (release merge or tag), never by a feature PR.

## Advisory
- A repo's own CLAUDE.md or rule files MAY override this default (e.g. trunk-based repos with no `develop`) — a repo-level rule takes precedence.
