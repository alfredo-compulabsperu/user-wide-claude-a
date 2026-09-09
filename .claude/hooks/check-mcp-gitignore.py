#!/usr/bin/env python3
"""PreToolUse hook: block Write/Edit on .mcp.json unless the enclosing git
repo already gitignores it. Prevents literal secrets from being committed
via .mcp.json env blocks. See ~/.claude/rules/secrets-and-env.md.
"""
import json
import os
import subprocess
import sys

try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(0)

file_path = payload.get("tool_input", {}).get("file_path", "")
if not file_path or os.path.basename(file_path) != ".mcp.json":
    sys.exit(0)

directory = os.path.dirname(file_path) or "."


def run(cmd):
    return subprocess.run(cmd, cwd=directory, capture_output=True, text=True)


repo_root = run(["git", "rev-parse", "--show-toplevel"])
if repo_root.returncode != 0:
    sys.exit(0)  # not a git repo, nothing to guard

ignored = run(["git", "check-ignore", "-q", os.path.basename(file_path)])
if ignored.returncode != 0:
    print(f"BLOCKED: {file_path} is not gitignored in {repo_root.stdout.strip()}.", file=sys.stderr)
    print("Add '.mcp.json' to .gitignore first, or use ${VAR} references only -- never literal secret values.", file=sys.stderr)
    print("See ~/.claude/rules/secrets-and-env.md", file=sys.stderr)
    sys.exit(2)

sys.exit(0)
