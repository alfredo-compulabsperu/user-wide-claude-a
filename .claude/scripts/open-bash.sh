#!/usr/bin/env bash
# open-bash.sh — split the current tmux pane and open bash in the worktree root
#
# Usage:
#   open-bash [-h]   # horizontal split (default)
#   open-bash -v     # vertical split

set -euo pipefail

split_direction="-h"

for arg in "$@"; do
  case "$arg" in
    -v) split_direction="-v" ;;
    -h) split_direction="-h" ;;
    *)  echo "open-bash: unknown flag '$arg' (use -h or -v)" >&2; exit 1 ;;
  esac
done

# Resolve worktree root; fall back to $PWD
worktree_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")

if [[ -z "${TMUX:-}" ]]; then
  echo "open-bash: not inside a tmux session" >&2
  exit 1
fi

tmux split-window "$split_direction" -c "$worktree_root" bash
