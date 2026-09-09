#!/usr/bin/env python3
"""PreToolUse hook: block trivial no-op Bash calls used as placeholder/pacing
filler (e.g. `true`, `:`, an empty command, or a comment-only line) with no
description that justifies them. Caught twice in one session (2026-09) as
wasted tool calls with no observation or state-mutation purpose. See
~/.claude/rules/ (Bash tool guidance: avoid pointless tool calls).
"""
import json
import re
import sys

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)

if payload.get("tool_name") != "Bash":
    sys.exit(0)

command = (payload.get("tool_input", {}).get("command") or "").strip()

# Strip trailing/leading shell comments and whitespace-only lines to find
# the "real" command content.
stripped = re.sub(r"#.*$", "", command, flags=re.MULTILINE).strip()

NOOP_PATTERNS = {"true", ":", ""}

if stripped in NOOP_PATTERNS:
    print(
        "BLOCKED: this Bash command is a no-op placeholder "
        f"({command!r}) with no observation or state-mutation effect.",
        file=sys.stderr,
    )
    print(
        "If you don't need a tool call right now, just write your next "
        "message directly instead of running a filler command.",
        file=sys.stderr,
    )
    sys.exit(2)

sys.exit(0)
