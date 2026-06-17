#!/usr/bin/env bash
# gh-lib.sh — shared helpers for GitHub URL scripts
# Source this file; do not execute directly.

# resolve_github_base_url: sets $base_url from git remote origin.
# Handles git@github.com:, ssh://git@github.com/, and https://github.com/ forms.
resolve_github_base_url() {
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null) || {
    echo "error: no git remote 'origin' found" >&2; return 1
  }
  if [[ "$remote_url" =~ ^git@github\.com:(.+)$ ]]; then
    remote_url="https://github.com/${BASH_REMATCH[1]}"
  elif [[ "$remote_url" =~ ^ssh://git@github\.com/(.+)$ ]]; then
    remote_url="https://github.com/${BASH_REMATCH[1]}"
  fi
  base_url="${remote_url%.git}"
  [[ "$base_url" == *"github.com"* ]] || {
    echo "error: remote origin is not a GitHub URL: $remote_url" >&2; return 1
  }
}

# open_urls: print each URL to stdout, then try to open them in the system browser.
# Browser failures are intentionally suppressed — printing URLs is the primary contract.
open_urls() {
  local urls=("$@")
  for url in "${urls[@]}"; do echo "$url"; done
  if command -v xdg-open &>/dev/null; then
    for url in "${urls[@]}"; do xdg-open "$url" &>/dev/null & disown; done
  elif command -v open &>/dev/null; then
    for url in "${urls[@]}"; do open "$url" &>/dev/null & disown; done
  fi
}
