#!/usr/bin/env python3
"""PostToolUse:EnterPlanMode -- inject the plan-mode-exit lazy rule as additionalContext."""
import json
import sys

RULE_PATH = "/home/alfredo/.claude/lazy/rules/plan.md"


def main():
    try:
        with open(RULE_PATH, "r") as f:
            rule_text = f.read()
    except OSError as e:
        print(f"enterplanmode-rule-inject: could not read {RULE_PATH}: {e}", file=sys.stderr)
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
