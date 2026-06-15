#!/usr/bin/env bash
# open-gh-issue.sh -- output GitHub issue URLs by ID(s) or natural-language search
#
# Usage:
#   open-gh-issue <id> [id ...]
#   open-gh-issue that fixes the login bug
#   open-gh-issue relates to authentication

set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "Usage: open-gh-issue <id> [id ...]" >&2
  echo "       open-gh-issue <natural language query>" >&2
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
repo_path="${base_url#https://github.com/}"

# Detect mode: all-numeric args → direct IDs; anything else → natural search
all_numeric=true
for arg in "$@"; do
  [[ "$arg" =~ ^[0-9]+$ ]] || { all_numeric=false; break; }
done

open_urls() {
  local urls=("$@")
  for url in "${urls[@]}"; do echo "$url"; done
  if command -v xdg-open &>/dev/null; then
    for url in "${urls[@]}"; do xdg-open "$url" &>/dev/null & done
  elif command -v open &>/dev/null; then
    for url in "${urls[@]}"; do open "$url" &>/dev/null & done
  fi
}

if $all_numeric; then
  urls=()
  for id in "$@"; do urls+=("${base_url}/issues/${id}"); done
  open_urls "${urls[@]}"
else
  # Strip a leading "that" conjunction — it's a stopword in search
  query="$*"
  query="${query#that }"

  raw=$(gh search issues --repo "$repo_path" -- "$query" \
        --json number,url --limit 20 2>/dev/null)

  urls=()
  while IFS= read -r url; do
    [[ -n "$url" ]] && urls+=("$url")
  done < <(printf '%s' "$raw" | python3 -c "
import json, sys
for item in json.load(sys.stdin):
    print(item['url'])
")

  if [[ ${#urls[@]} -eq 0 ]]; then
    echo "no issues found for: $query" >&2
    exit 1
  fi

  open_urls "${urls[@]}"
fi
