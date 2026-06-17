#!/usr/bin/env bash
# open-gh-issue.sh -- output GitHub issue URLs by ID(s) or natural-language search
#
# Usage:
#   open-gh-issue <id> [id ...]
#   open-gh-issue that fixes the login bug
#   open-gh-issue relates to authentication

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gh-lib.sh
source "${SCRIPT_DIR}/gh-lib.sh"

if [[ $# -eq 0 ]]; then
  echo "Usage: open-gh-issue <id> [id ...]" >&2
  echo "       open-gh-issue <natural language query>" >&2
  exit 1
fi

resolve_github_base_url || exit 1
repo_path="${base_url#https://github.com/}"

# Detect mode: all-numeric args → direct IDs; anything else → natural search
all_numeric=true
for arg in "$@"; do
  [[ "$arg" =~ ^[0-9]+$ ]] || { all_numeric=false; break; }
done

if $all_numeric; then
  urls=()
  for id in "$@"; do urls+=("${base_url}/issues/${id}"); done
  open_urls "${urls[@]}"
else
  # Strip leading "that " so "open-gh-issue that fixes X" becomes "fixes X"
  query="$*"
  query="${query#that }"

  raw=$(gh search issues --repo "$repo_path" --state open -- "$query" \
        --json number,url --limit 20) || {
    echo "error: gh search failed for repo '$repo_path', query: $query" >&2; exit 1
  }

  parsed=$(printf '%s' "$raw" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if not isinstance(data, list):
    print(f'unexpected gh response: {json.dumps(data)}', file=sys.stderr)
    sys.exit(1)
for item in data:
    print(item['url'].strip())
") || {
    echo "error: failed to parse gh output. raw response:" >&2
    printf '%s\n' "$raw" >&2
    exit 1
  }

  urls=()
  while IFS= read -r url; do
    url="${url%$'\r'}"
    [[ -n "$url" ]] && urls+=("$url")
  done <<< "$parsed"

  if [[ ${#urls[@]} -eq 0 ]]; then
    echo "no issues found for: $query" >&2
    exit 1
  fi

  open_urls "${urls[@]}"
fi
