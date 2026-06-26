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
# Returns 0 if <flag> appears as a flag in the argument list (skipping values
# that follow -w so a value that looks like a flag isn't misidentified).
has_flag() {
  local flag="$1" skip_next=0
  shift
  for arg in "$@"; do
    if (( skip_next )); then skip_next=0; continue; fi
    [[ "$arg" == "-w" ]] && { skip_next=1; continue; }
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
# Prints the value following <flag>. Exits 1 with an error if <flag> is the
# last argument with no following value. Prints nothing and returns 0 if absent.
get_flag_value() {
  local flag="$1"
  shift
  local prev=""
  for arg in "$@"; do
    if [[ "$prev" == "$flag" ]]; then
      printf '%s\n' "$arg"
      return 0
    fi
    prev="$arg"
  done
  if [[ "$prev" == "$flag" ]]; then
    printf 'error: %s requires a value\n' "$flag" >&2
    exit 1
  fi
}

# strip_w_flag <args...>
# Removes -w <value>; prints remaining args NUL-delimited.
# Preserves -p/--print so they reach claude when in the passthrough path.
strip_w_flag() {
  local skip_next=0
  for arg in "$@"; do
    if (( skip_next )); then skip_next=0; continue; fi
    [[ "$arg" == "-w" ]] && { skip_next=1; continue; }
    printf '%s\0' "$arg"
  done
}

# strip_wrapper_flags <args...>
# Removes -w <value>, -p, and --print; prints remaining args NUL-delimited.
# Used only in the tmux-passthrough path where -p/--print are wrapper signals.
strip_wrapper_flags() {
  local skip_next=0
  for arg in "$@"; do
    if (( skip_next )); then skip_next=0; continue; fi
    case "$arg" in
      -p|--print) continue ;;
      -w) skip_next=1; continue ;;
    esac
    printf '%s\0' "$arg"
  done
}

# collect_stripped_args <strip_fn> <args...>
# Runs <strip_fn> over <args> and collects NUL-delimited output into the
# global array $stripped_args. Compatible with bash 3.2+.
collect_stripped_args() {
  local strip_fn="$1"
  shift
  stripped_args=()
  while IFS= read -r -d '' arg; do
    stripped_args+=("$arg")
  done < <("$strip_fn" "$@")
}

if [[ -n "${TMUX:-}" ]] && ! has_flag "-p" "$@" && ! has_flag "--print" "$@"; then
  # Determine window name: -w flag takes precedence over worktree name
  window_name=$(get_flag_value "-w" "$@") || exit 1
  if [[ -z "$window_name" ]]; then
    window_name=$(get_worktree_name)
  fi

  # Build command string, stripping only -w <value>
  collect_stripped_args strip_w_flag "$@"
  cmd="claude"
  for arg in "${stripped_args[@]}"; do
    cmd="${cmd} $(printf '%q' "$arg")"
  done

  tmux new-window -n "$window_name" -c "$PWD" bash -c "$cmd" || {
    echo "error: tmux new-window failed; falling back to exec" >&2
    exec claude "${stripped_args[@]}"
  }
else
  if [[ -n "${TMUX:-}" ]]; then
    # -p/--print triggered passthrough inside tmux; they are wrapper signals here
    collect_stripped_args strip_wrapper_flags "$@"
  else
    # Outside tmux: only -w is a wrapper flag; preserve -p/--print for claude
    collect_stripped_args strip_w_flag "$@"
  fi
  exec claude "${stripped_args[@]}"
fi
