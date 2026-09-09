#!/usr/bin/env python3
"""PostToolUse:Skill -- when the invoked skill is research-ops, inject the
research-ops lazy rule (call syntax + fork/parallelism policy) as
additionalContext. See ~/.claude/lazy/rules/research-ops.md.
"""
import json
import sys

RULE_PATH = "/home/alfredo/.claude/lazy/rules/research-ops.md"


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    skill = payload.get("tool_input", {}).get("skill", "")
    if skill.split(":")[-1] != "research-ops":
        sys.exit(0)

    try:
        with open(RULE_PATH, "r") as f:
            rule_text = f.read()
    except OSError as e:
        print(f"research-ops-rule-inject: could not read {RULE_PATH}: {e}", file=sys.stderr)
        sys.exit(0)

    output = {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": rule_text,
        }
    }
    print(json.dumps(output))
    sys.exit(0)


if __name__ == "__main__":
    main()
