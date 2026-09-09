---
paths:
  - "**/settings.json"
  - "**/settings.local.json"
on:
  tools: [Edit, Write, Bash]
  paths: ["**/settings.json", "**/settings.local.json"]
  commands: ["*settings.json*", "*settings.local.json*"]
---
# Settings.json Secrets

| Rule | Requirement |
|---|---|
| Committed settings | `.claude/settings.json` (project-level, typically committed) MUST NOT contain secrets or credentials — not in its `env` block, not anywhere else in the file. |
| Local settings | `.claude/settings.local.json` (uncommitted, per-checkout) SHOULD NOT contain secrets or credentials either, even though it is typically gitignored. |
| User-wide settings | `~/.claude/settings.json` is subject to the same MUST NOT as project-level `settings.json` — it is a single shared file across every repo/worktree on the machine, not a per-project local override. |
| Centralized storage | Secrets and credentials MUST instead be stored centrally — e.g. `~/.bashrc` — per `secrets-and-env.md`, exported under a distinct name when the value differs from another variable already using that name, and referenced from there rather than duplicated into a settings file. |
| No expansion available | Unlike `.mcp.json` (see `secrets-and-env.md`), Claude Code's `settings.json`/`settings.local.json` `env` key does NOT support `${VAR}` expansion — confirmed against Claude Code's own docs 2026-08-26. Any value placed there is used literally, verbatim, as the environment variable's value. There is no "reference, don't store" option for this file: a Claude Code session already inherits its parent shell's exported environment automatically, so a secret that needs to reach a session should be exported in `~/.bashrc` (or an equivalent centralized store) and simply left out of this file — not "pointed at" from it. |
| Rationale | Discovered 2026-08-26: a live GitHub personal access token was found stored as a literal value in `core-business/.claude/settings.local.json`'s `env` block. The first attempted fix — replacing the literal with a `${VAR}`-style reference — silently broke the credential, because `settings.json`'s `env` key has no expansion mechanism and just sets the literal string `${VAR_NAME}` as the value. Reverting that specific edit was then blocked by the auto-mode safety classifier (writing a bare secret value back into a file is exactly the kind of action it's designed to catch), leaving the file broken until the user manually restored it. The only fix that actually avoids this trap is never storing the secret in the file in the first place. |
| Scope | Applies to `~/.claude/settings.json`, `.claude/settings.json`, and `.claude/settings.local.json` at every path level (root repo, any worktree). |
| Enforcement | Backed by a PreToolUse hook (`~/.claude/hooks/check-settings-json-secrets.sh`) that scans Write/Edit content targeting `settings.json`/`settings.local.json` for common secret-shaped patterns (GitHub tokens, AWS keys, Anthropic/OpenAI-style keys, Slack tokens, Google API keys, JWTs) and blocks with exit code 2 — not prose alone. The pattern list is a heuristic, not exhaustive; it won't catch every secret shape, and it cannot catch a secret already present in a file before the hook existed (grep for known prefixes to check retroactively). |
