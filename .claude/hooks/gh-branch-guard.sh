#!/usr/bin/env bash
# Guards against:
#   1. gh pr create targeting main/master (or missing --base)
#   2. git commit while on main/master
#   3. git push to main/master (explicit or bare)
#   4. gh repo create without an explicit --private/--public visibility flag
# Reads hook input from stdin as JSON (Claude Code PreToolUse:Bash format).

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Fast exit — skip entirely if no relevant command present
if ! echo "$COMMAND" | grep -qE '(gh pr create|git commit|git push|gh repo create)'; then
  exit 0
fi

PROTECTED="main|master"
INTEGRATION="develop"

# A PreToolUse decision must nest under hookSpecificOutput; a bare top-level
# permissionDecision is ignored and exit 0 means ALLOW (audit BROKEN_DENY).
deny() {
  jq -n --arg reason "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
}

# --- gh pr create: must target develop ---
if echo "$COMMAND" | grep -q 'gh pr create'; then
  if echo "$COMMAND" | grep -qE -- "--base (${PROTECTED})"; then
    BASE=$(echo "$COMMAND" | grep -oE "(${PROTECTED})" | head -1)
    deny "PRs must target '${INTEGRATION}', not '${BASE}'. Replace --base with --base ${INTEGRATION}."
  fi
  if ! echo "$COMMAND" | grep -q -- '--base'; then
    deny "No --base specified. gh defaults to the repo default branch. Add --base ${INTEGRATION} explicitly."
  fi
fi

# --- git commit: block if on main/master ---
if echo "$COMMAND" | grep -qE '(^|&&|;)\s*git commit'; then
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  if echo "$BRANCH" | grep -qE "^(${PROTECTED})$"; then
    deny "Direct commits to '${BRANCH}' are not allowed. Create a feature branch first."
  fi
fi

# --- gh repo create: must explicitly declare visibility, default to private ---
if echo "$COMMAND" | grep -q 'gh repo create'; then
  HAS_PUBLIC=$(echo "$COMMAND" | grep -qE -- '(--public|\bpublic\b)' && echo 1 || echo 0)
  HAS_PRIVATE=$(echo "$COMMAND" | grep -qE -- '--private' && echo 1 || echo 0)
  if [[ "$HAS_PUBLIC" == "0" && "$HAS_PRIVATE" == "0" ]]; then
    deny "gh repo create must explicitly specify --private or --public. Repos default to private unless public was explicitly requested — add --private (or --public if that was actually intended)."
  fi
fi

# --- git push: block explicit or bare push to main/master ---
if echo "$COMMAND" | grep -qE 'git push'; then
  if echo "$COMMAND" | grep -qE "git push\s+\S+\s+(${PROTECTED})(\s|$)"; then
    BRANCH=$(echo "$COMMAND" | grep -oE "(${PROTECTED})" | head -1)
    deny "Pushing directly to '${BRANCH}' is not allowed. Open a PR targeting ${INTEGRATION} instead."
  fi
  if ! echo "$COMMAND" | grep -qE "git push\s+\S+\s+\S+"; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if echo "$BRANCH" | grep -qE "^(${PROTECTED})$"; then
      deny "Pushing directly to '${BRANCH}' is not allowed. Open a PR targeting ${INTEGRATION} instead."
    fi
  fi
fi
