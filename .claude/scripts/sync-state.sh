#!/usr/bin/env bash
# sync-state.sh — get/set the last-synced SHA-256 baseline for a sync artifact.
#
# Usage:
#   sync-state.sh get <key>              Print stored SHA-256 for <key>,
#                                         or empty string if absent/file missing.
#   sync-state.sh set <key> <sha256>     Atomically record/update the baseline.
#
# State lives in $HOME/.claude/.sync-state.json, a flat {"key": "sha256"} map.
# No `unset` subcommand — a stale key is harmless dead data (YAGNI).
set -euo pipefail

STATE_FILE="$HOME/.claude/.sync-state.json"

usage() {
  echo "Usage: sync-state.sh get <key> | set <key> <sha256>" >&2
  exit 1
}

[[ $# -ge 1 ]] || usage

CMD="$1"; shift

case "$CMD" in
  get)
    [[ $# -eq 1 ]] || usage
    # Single-quoted heredoc delimiter + env-var passing prevent shell injection (mirrors sync.sh C1)
    STATE_FILE="$STATE_FILE" KEY="$1" python3 - <<'PYEOF'
import json, os

path = os.environ['STATE_FILE']
key = os.environ['KEY']
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
print(data.get(key, ''))
PYEOF
    ;;
  set)
    [[ $# -eq 2 ]] || usage
    mkdir -p "$(dirname "$STATE_FILE")"
    # Atomic write: tempfile in the same dir + os.replace — readers never see a half-written file
    STATE_FILE="$STATE_FILE" KEY="$1" SHA="$2" python3 - <<'PYEOF'
import json, os, tempfile

path = os.environ['STATE_FILE']
key = os.environ['KEY']
sha = os.environ['SHA']
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
data[key] = sha
dir_name = os.path.dirname(path) or '.'
fd, tmp_path = tempfile.mkstemp(dir=dir_name)
try:
    with os.fdopen(fd, 'w') as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write('\n')
    os.replace(tmp_path, path)
except BaseException:
    os.unlink(tmp_path)
    raise
PYEOF
    ;;
  *)
    usage
    ;;
esac
