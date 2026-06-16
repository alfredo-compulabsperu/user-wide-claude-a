#!/usr/bin/env bash
# rename-tmux-window.sh — rename the current tmux window; errors if not in tmux or name conflicts

set -euo pipefail

NAME="${1:-}"

if [[ -z "$NAME" ]]; then
  # Compute default: strip "worktree-" prefix from branch if it matches the worktree
  # folder name; otherwise use the worktree folder name as-is.
  WORKTREE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -z "$WORKTREE_ROOT" ]]; then
    echo "Usage: rename-tmux-window.sh <name>" >&2
    exit 1
  fi
  WORKTREE_FOLDER=$(basename "$WORKTREE_ROOT")
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  BRANCH_STRIPPED="${BRANCH#worktree-}"
  if [[ "$BRANCH_STRIPPED" == "$WORKTREE_FOLDER" ]]; then
    NAME="$BRANCH_STRIPPED"
  else
    NAME="$WORKTREE_FOLDER"
  fi
fi

# Must be inside tmux
if [[ -z "${TMUX:-}" ]]; then
  echo "Error: not inside a tmux session." >&2
  exit 1
fi

# Get current window id — target $TMUX_PANE so subprocess invocations resolve the
# correct window rather than the client's last-focused window.
CURRENT_ID=$(tmux display-message -t "${TMUX_PANE:-}" -p '#I')

# Check for name conflict across all windows in this session
CONFLICT=$(tmux list-windows -F '#I #W' | awk -v name="$NAME" -v cur="$CURRENT_ID" '$2 == name && $1 != cur {print $1}')

if [[ -n "$CONFLICT" ]]; then
  echo "Error: window name \"${NAME}\" is already used by window ${CONFLICT}." >&2
  exit 1
fi

tmux rename-window -t "$CURRENT_ID" "$NAME"
echo "Window ${CURRENT_ID} renamed to \"${NAME}\"."
