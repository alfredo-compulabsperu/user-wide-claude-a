#!/usr/bin/env python3
"""UserPromptSubmit -- catches /research-ops invoked as a native slash command.

Native slash-command invocation of /research-ops never emits a `Skill`
tool_use event (the harness pre-expands the command directly into the
conversation), so the existing PreToolUse:Skill / PostToolUse:Skill hooks
(research-ops-tooling-gate.py / research-ops-rule-inject.py) never fire for
it -- confirmed by manual replay 2026-08-31. This hook covers that path by
matching on the raw prompt text instead of a tool call.

Mirrors both existing hooks in one pass:
1. Blocks (exit 2) if the Exa plugin isn't enabled -- same policy as
   research-ops-tooling-gate.py.
2. Otherwise injects ~/.claude/lazy/rules/research-ops.md as additionalContext
   -- same content as research-ops-rule-inject.py.

The PreToolUse:Skill / PostToolUse:Skill hooks are left in place for the
complementary case: the assistant explicitly calling the Skill tool with
skill="research-ops" (e.g. from within an agentic flow, not a user-typed
slash command) -- that path still emits a Skill tool_use event and this
UserPromptSubmit hook won't have fired for it (no new user prompt).
"""
import json
import os
import re
import subprocess
import sys

RULE_PATH = "/home/alfredo/.claude/lazy/rules/research-ops.md"
USER_SETTINGS = os.path.expanduser("~/.claude/settings.json")
USER_SETTINGS_LOCAL = os.path.expanduser("~/.claude/settings.local.json")

PROMPT_RE = re.compile(r"^\s*/research-ops\b", re.IGNORECASE)


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

    prompt = payload.get("prompt") or payload.get("message") or ""
    if not PROMPT_RE.match(prompt):
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

    try:
        with open(RULE_PATH, "r") as f:
            rule_text = f.read()
    except OSError as e:
        print(f"research-ops-promptsubmit: could not read {RULE_PATH}: {e}", file=sys.stderr)
        sys.exit(0)

    output = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": rule_text,
        }
    }
    print(json.dumps(output))
    sys.exit(0)


if __name__ == "__main__":
    main()
