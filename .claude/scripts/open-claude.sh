#!/usr/bin/env bash
# open-claude.sh — launch claude in a new tmux window
#
# Usage:
#   open-claude [-w <name>] [claude-args...]
#   open-claude -p [claude-args...]   # passthrough: exec claude directly

set -euo pipefail

get_worktree_name() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$root" ]]; then
    basename "$root"
  else
    echo "claude"
  fi
}

window_name=""
passthrough=false
claude_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -w) shift; window_name="${1:-}"; claude_args+=("-w" "${window_name}"); shift ;;
    -p|--print) passthrough=true; shift ;;
    *) claude_args+=("$1"); shift ;;
  esac
done

if [[ "$passthrough" == true ]]; then
  exec claude "${claude_args[@]+"${claude_args[@]}"}"
fi

[[ -n "${TMUX:-}" ]] || { echo "error: not inside a tmux session" >&2; exit 1; }

[[ -z "$window_name" ]] && window_name="$(get_worktree_name)"

cmd="claude"
for arg in "${claude_args[@]+"${claude_args[@]}"}"; do
  cmd="${cmd} $(printf '%q' "$arg")"
done

session=$(tmux display-message -p '#S' 2>/dev/null || true)
tmux new-window -t "$session" -n "$window_name" -c "$PWD" bash -c "$cmd" || {
  echo "error: tmux new-window failed; falling back to exec" >&2
  exec claude "${claude_args[@]+"${claude_args[@]}"}"
}
