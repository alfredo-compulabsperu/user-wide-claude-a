#!/usr/bin/env python3
"""PreToolUse:Skill -- hard-block /research-ops if the Exa plugin isn't
enabled. Enforces the "Required tooling" section of
~/.claude/lazy/rules/research-ops.md: no silent fallback to WebSearch/WebFetch.

Caveat: this only checks *enablement* recorded in settings.json
(enabledPlugins), which is all a stateless hook can see statically. It cannot
detect a plugin that's enabled but whose MCP server failed to actually start
-- that failure mode isn't caught here.
"""
import json
import os
import subprocess
import sys

USER_SETTINGS = os.path.expanduser("~/.claude/settings.json")
USER_SETTINGS_LOCAL = os.path.expanduser("~/.claude/settings.local.json")


def load_enabled_plugins(path):
    try:
        with open(path, "r") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}
    return data.get("enabledPlugins", {})


def repo_root(cwd):
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=cwd, capture_output=True, text=True, timeout=5,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return None


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    skill = payload.get("tool_input", {}).get("skill", "")
    if skill.split(":")[-1] != "research-ops":
        sys.exit(0)

    cwd = payload.get("cwd") or os.getcwd()

    merged = {}
    merged.update(load_enabled_plugins(USER_SETTINGS))
    merged.update(load_enabled_plugins(USER_SETTINGS_LOCAL))

    root = repo_root(cwd)
    if root:
        merged.update(load_enabled_plugins(os.path.join(root, ".claude", "settings.json")))
        merged.update(load_enabled_plugins(os.path.join(root, ".claude", "settings.local.json")))

    exa_enabled = any(k.split("@")[0] == "exa" and v for k, v in merged.items())

    if not exa_enabled:
        print(
            "BLOCKED: /research-ops requires the Exa plugin (web_search_exa) to be enabled -- "
            "no fallback to WebSearch/WebFetch is allowed. Enable it (e.g. `/plugin`, install "
            "'exa'), then retry.",
            file=sys.stderr,
        )
        print("See ~/.claude/lazy/rules/research-ops.md -- Required tooling.", file=sys.stderr)
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
