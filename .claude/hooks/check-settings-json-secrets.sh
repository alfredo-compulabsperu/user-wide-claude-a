#!/usr/bin/env bash
# PreToolUse hook: block Write/Edit on settings.json / settings.local.json
# when the content being written contains a literal secret-shaped value.
# settings.json's `env` key does NOT support ${VAR} expansion (confirmed
# 2026-08-26) -- a secret must be omitted from this file entirely and
# exported in ~/.bashrc instead (see secrets-and-env.md); a session already
# inherits its parent shell's exported environment automatically.
# See ~/.claude/rules/settings-json-secrets.md.
set -euo pipefail

# Fail closed: this guard protects the one file class that once held a live
# PAT, so a missing or failing jq must deny, not silently allow.
blocked() {
  echo "BLOCKED: $1 -- refusing the write rather than skipping the secret check." >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || blocked "jq is not installed, cannot inspect the payload"

payload="$(cat)"

file_path="$(jq -r '.tool_input.file_path // empty' <<<"$payload")" || blocked "jq could not parse the hook payload"
[ -z "$file_path" ] && exit 0

base="$(basename -- "$file_path")"
case "$base" in
  settings.json|settings.local.json) ;;
  *) exit 0 ;;
esac

text="$(jq -r '
  [.tool_input.content, .tool_input.new_string,
   (.tool_input.edits // [])[]?.new_string]
  | map(select(. != null)) | join("\n")
' <<<"$payload")" || blocked "jq could not extract the written content"
[ -z "$text" ] && exit 0

pattern='gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-(ant-|proj-)?[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{35}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'

hit="$(grep -oE "$pattern" <<<"$text" | head -1 || true)"
if [ -n "$hit" ]; then
  echo "BLOCKED: $file_path write contains a literal secret-shaped value (${hit:0:12}...)." >&2
  echo "settings.json's env key does NOT expand \${VAR} -- omit this value from the file entirely and export it in ~/.bashrc instead (see secrets-and-env.md); a session inherits its parent shell's environment automatically." >&2
  echo "See ~/.claude/rules/settings-json-secrets.md" >&2
  exit 2
fi

exit 0
