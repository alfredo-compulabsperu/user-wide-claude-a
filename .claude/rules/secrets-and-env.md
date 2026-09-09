# Secrets and Environment Variables

## Required

A repo's `.mcp.json` `env` blocks MUST use `${VAR}` references for secrets and shared config, not literal hardcoded values — the file is a config surface, not a secrets store. Any git repo containing a `.mcp.json` MUST list it in `.gitignore` before it's first written there, so a literal value never lands in git history by accident. This is backed by a PreToolUse hook (`~/.claude/hooks/check-mcp-gitignore.py`) that blocks Write/Edit on `.mcp.json` when the enclosing git repo doesn't gitignore it yet. If a `.mcp.json` is already tracked with literal values (not just newly written), the hook won't catch it retroactively — check with `git ls-files -- .mcp.json` plus `git check-ignore -q .mcp.json` per repo, `git rm --cached` it, gitignore it, and rewrite the literals to `${VAR}` refs.

`${VAR}` expansion is not universal, though — it does not work in every Claude Code config surface. Confirmed not to expand inside `~/.claude.json`'s `mcpServers.*.env` block specifically (a literal, un-expanded `${VAR}` string showed up in a live OAuth URL there); that file is local-machine-only and never committed to git, so literal values are the correct, deliberate choice in that one location — do not "fix" it by converting to `${VAR}` syntax.

## Recommended

Common environment variables and secrets SHOULD live in `~/.bashrc` (directly, or via a file it sources, e.g. `~/.config/environment.d/*.conf`) rather than duplicated across per-project `settings.json`, `.mcp.json`, or `.env` files. A variable qualifies as "common" when its value is identical everywhere it's currently defined and it isn't inherently session/host-scoped (e.g. `DISPLAY`, which must track the active X session, not a frozen value). A tool's own config expressed via an `env` key in its native config file (e.g. Claude Code's `CLAUDE_CODE_*`/`ECC_*` flags in `settings.json`) is config, not a generic environment variable, even when its value happens to be identical everywhere — it SHOULD stay in that tool's config file, not move to `.bashrc`.

`~/.bashrc` only executes for interactive shells (the standard `case $- in *i*) ;; *) return;; esac` guard at its top returns immediately for non-interactive callers, regardless of login status) — do not assume `.bashrc` reaches non-interactive shells, cron jobs, or systemd units. Those need the variable declared explicitly at the launch point instead (`Environment=`, a per-server `env` block, a crontab line).
