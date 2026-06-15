#!/usr/bin/env bash
# open-gh-pr.sh -- output GitHub pull request URLs by ID(s)
#
# Usage:
#   open-gh-pr <id> [id ...]

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: open-gh-pr <id> [id ...]" >&2
  exit 1
fi

# Resolve repo from git remote origin
remote_url=$(git remote get-url origin 2>/dev/null) || {
  echo "error: no git remote 'origin' found" >&2; exit 1
}
[[ "$remote_url" =~ ^git@github\.com:(.+)$ ]] && remote_url="https://github.com/${BASH_REMATCH[1]}"
base_url="${remote_url%.git}"
[[ "$base_url" != *"github.com"* ]] && {
  echo "error: remote origin is not a GitHub URL: $remote_url" >&2; exit 1
}

urls=()
for id in "$@"; do
  if ! [[ "$id" =~ ^[0-9]+$ ]]; then
    echo "error: '$id' is not a valid PR number" >&2; exit 1
  fi
  urls+=("${base_url}/pull/${id}")
done

for url in "${urls[@]}"; do echo "$url"; done

if command -v xdg-open &>/dev/null; then
  for url in "${urls[@]}"; do xdg-open "$url" &>/dev/null & done
elif command -v open &>/dev/null; then
  for url in "${urls[@]}"; do open "$url" &>/dev/null & done
fi
