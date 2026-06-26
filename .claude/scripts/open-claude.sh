#!/usr/bin/env bash
# open-claude.sh — launch claude CLI; opens a named tmux window when inside tmux
#
# Usage:
#   open-claude [args...]
#   open-claude -w <name> [args...]  # set tmux window name to <name>
#   open-claude -p [args...]         # force passthrough (no new tmux window)
#   open-claude --print [args...]    # same as -p

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
  local root name
  root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$root" ]]; then
    name=$(basename "$root")
    echo "${name:-claude}"
  else
    echo "claude"
  fi
}

# get_flag_value <flag> <args...>
# Returns the value following <flag> in the argument list, or empty string.
get_flag_value() {
  local flag="$1"
  shift
  local prev=""
  for arg in "$@"; do
    if [[ "$prev" == "$flag" ]]; then
      echo "$arg"
      return 0
    fi
    prev="$arg"
  done
}

# strip_wrapper_flags <args...>
# Removes -p, --print and -w <value> from the argument list; prints remaining
# args NUL-delimited (for use with `mapfile -d ''`).
strip_wrapper_flags() {
  local skip_next=0
  for arg in "$@"; do
    if (( skip_next )); then
      skip_next=0
      continue
    fi
    case "$arg" in
      -p|--print) continue ;;
      -w) skip_next=1; continue ;;
    esac
    printf '%s\0' "$arg"
  done
}

if [[ -n "${TMUX:-}" ]] && ! has_flag "-p" "$@" && ! has_flag "--print" "$@"; then
  # Determine window name: -w flag takes precedence over worktree name
  window_name=$(get_flag_value "-w" "$@")
  if [[ -z "$window_name" ]]; then
    window_name=$(get_worktree_name)
  fi

  # Build command string, stripping all wrapper-only flags
  mapfile -d '' stripped_args < <(strip_wrapper_flags "$@")
  cmd="claude"
  for arg in "${stripped_args[@]}"; do
    cmd="${cmd} $(printf '%q' "$arg")"
  done

  tmux new-window -n "$window_name" bash -c "$cmd" || {
    echo "error: tmux new-window failed; falling back to exec" >&2
    exec claude "${stripped_args[@]}"
  }
else
  # Strip all wrapper-only flags before handing off to claude
  mapfile -d '' passthrough_args < <(strip_wrapper_flags "$@")
  exec claude "${passthrough_args[@]}"
fi
