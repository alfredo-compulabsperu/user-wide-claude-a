# PR Base Branch

## Required
- When assessing branch or repo state (ahead/behind, diffs, "what changed"), MUST compare against `develop` first, not `main`. The session's default-branch hint MUST NOT override this. (The PR-target rule itself loads when a `gh pr create` is about to run.)
