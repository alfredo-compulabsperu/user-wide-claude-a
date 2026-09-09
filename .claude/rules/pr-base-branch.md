# PR Base Branch

## Required
- All PRs MUST target `develop` — MUST NOT target `main` or `master`. `main` advances only by promoting `develop` (release merge or tag), never by a feature PR.
- When assessing branch or repo state (ahead/behind, diffs, "what changed"), MUST compare against `develop` first, not `main`. The session's default-branch hint MUST NOT override this.

## Advisory
- A repo's own CLAUDE.md or rule files MAY override this default (e.g. trunk-based repos with no `develop`) — a repo-level rule takes precedence.
