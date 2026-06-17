#!/usr/bin/env bash
# open-claude.sh — launch claude CLI; opens a named tmux window when inside tmux
#
# Usage:
#   open-claude [args...]
#   open-claude -p [args...]   # force passthrough (no new tmux window)
#   open-claude --print [args...] # same as -p

set -euo pipefail

# has_flag <flag> "$@"
# Returns 0 if <flag> appears in the argument list, 1 otherwise.
# Handles both short form (-x) and long form (--long).
has_flag() {
  local flag="$1"
  shift
  for arg in "$@"; do
    [[ "$arg" == "$flag" ]] && return 0
  done
  return 1
}

# get_worktree_name
# Returns the basename of the git worktree root, falling back to "claude".
get_worktree_name() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$root" ]]; then
    basename "$root"
  else
    echo "claude"
  fi
}

# strip_passthrough_flags <args...>
# Removes -p and --print from the argument list; prints remaining args NUL-delimited
# (for use with `mapfile -d ''`; NUL preserves args that contain spaces or newlines).
strip_passthrough_flags() {
  for arg in "$@"; do
    [[ "$arg" == "-p" || "$arg" == "--print" ]] && continue
    printf '%s\0' "$arg"
  done
}

if [[ -n "${TMUX:-}" ]] && ! has_flag "-p" "$@" && ! has_flag "--print" "$@"; then
  # Build a safely-quoted command string for tmux
  cmd="claude"
  for arg in "$@"; do
    cmd="${cmd} $(printf '%q' "$arg")"
  done
  tmux new-window -n "$(get_worktree_name)" "$cmd" || {
    echo "error: tmux new-window failed; falling back to exec" >&2
    mapfile -d '' passthrough_args < <(strip_passthrough_flags "$@")
    exec claude "${passthrough_args[@]}"
  }
else
  # Strip wrapper-only flags before handing off to claude
  mapfile -d '' passthrough_args < <(strip_passthrough_flags "$@")
  exec claude "${passthrough_args[@]}"
fi
