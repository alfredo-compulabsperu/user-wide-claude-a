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
if [[ -n "${TMUX_PANE:-}" ]]; then
  CURRENT_ID=$(tmux display-message -t "$TMUX_PANE" -p '#I') || {
    echo "error: could not determine current tmux window ID (stale TMUX_PANE?)" >&2; exit 1
  }
else
  CURRENT_ID=$(tmux display-message -p '#I') || {
    echo "error: could not determine current tmux window ID" >&2; exit 1
  }
fi

# Check for name conflict across all windows in this session
# Tab-delimited format avoids awk word-splitting on window names that contain spaces.
_windows=$(tmux list-windows -F $'#I\t#W') || {
  echo "error: tmux list-windows failed" >&2; exit 1
}
CONFLICT=$(awk -F'\t' -v name="$NAME" -v cur="$CURRENT_ID" '$2 == name && $1 != cur {print $1}' <<< "$_windows")

if [[ -n "$CONFLICT" ]]; then
  echo "Error: window name \"${NAME}\" is already used by window ${CONFLICT}." >&2
  exit 1
fi

tmux rename-window -t "$CURRENT_ID" "$NAME" || {
  echo "error: tmux rename-window failed for window ${CURRENT_ID}" >&2; exit 1
}
echo "Window ${CURRENT_ID} renamed to \"${NAME}\"."
