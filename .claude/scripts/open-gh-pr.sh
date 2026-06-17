#!/usr/bin/env bash
# open-gh-pr.sh -- output GitHub pull request URLs by ID(s)
#
# Usage:
#   open-gh-pr <id> [id ...]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gh-lib.sh
source "${SCRIPT_DIR}/gh-lib.sh"

if [[ $# -eq 0 ]]; then
  echo "Usage: open-gh-pr <id> [id ...]" >&2
  exit 1
fi

resolve_github_base_url || exit 1

urls=()
for id in "$@"; do
  if ! [[ "$id" =~ ^[0-9]+$ ]]; then
    echo "error: '$id' is not a valid PR number" >&2; exit 1
  fi
  urls+=("${base_url}/pull/${id}")
done

open_urls "${urls[@]}"
