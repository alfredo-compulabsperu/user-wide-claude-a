#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
MANIFEST="$REPO_DIR/manifest.yaml"

DRY_RUN=0
FORCE=0
SUBCOMMAND="install"

CNT_OK=0
CNT_UPDATED=0
CNT_MISSING=0
CNT_LOCAL_ONLY=0
CNT_MISSING_PLUGIN=0

usage() {
  cat >&2 <<EOF
Usage: sync.sh [OPTIONS] [SUBCOMMAND]

Subcommands:
  install   (default) Copy artifacts from repo to ~/.claude/

Options:
  -n, --dry-run   Report what would change without modifying ~/.claude/
  -f, --force     Overwrite existing files even when SHA-256 differs (no prompt)
  -h, --help      Show this help

EOF
  exit 0
}

# --- arg parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1 ;;
    -f|--force)   FORCE=1 ;;
    -h|--help)    usage ;;
    install)      SUBCOMMAND="install" ;;
    *)            echo "ERROR: unknown argument: $1" >&2; exit 1 ;;
  esac
  shift
done

# --- preflight ---
[[ -f "$MANIFEST" ]]  || { echo "ERROR: manifest.yaml not found at $REPO_DIR" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 required for YAML parsing" >&2; exit 1; }
[[ -d "$CLAUDE_DIR" ]] || { echo "ERROR: $CLAUDE_DIR does not exist" >&2; exit 1; }

# Stored as array so multi-word commands work safely with xargs -0 (C2)
SHA256_CMD=()
if command -v sha256sum >/dev/null 2>&1; then
  SHA256_CMD=(sha256sum)
elif command -v shasum >/dev/null 2>&1; then
  SHA256_CMD=(shasum -a 256)
else
  echo "ERROR: sha256sum or shasum not found" >&2; exit 1
fi

# --- YAML helpers ---
# Single-quoted heredoc delimiters + env-var passing prevent shell injection (C1)
yaml_get_names() {
  MANIFEST_PATH="$MANIFEST" SECTION="$1" python3 - <<'PYEOF'
import yaml, os
d = yaml.safe_load(open(os.environ['MANIFEST_PATH']))
for item in d.get(os.environ['SECTION'], []):
    if isinstance(item, dict):
        print(item.get('name', item.get('id', '')))
    else:
        print(item)
PYEOF
}

yaml_get_plugins() {
  MANIFEST_PATH="$MANIFEST" python3 - <<'PYEOF'
import yaml, os
d = yaml.safe_load(open(os.environ['MANIFEST_PATH']))
for p in d.get('plugins', []):
    print(p['id'] + '|' + p['marketplace'])
PYEOF
}

yaml_get_scripts() {
  MANIFEST_PATH="$MANIFEST" python3 - <<'PYEOF'
import yaml, os
d = yaml.safe_load(open(os.environ['MANIFEST_PATH']))
for s in d.get('scripts', []):
    exe = 'true' if s.get('executable') else 'false'
    print(s['name'] + '|' + exe)
PYEOF
}

yaml_get_claude_md_portable() {
  MANIFEST_PATH="$MANIFEST" python3 - <<'PYEOF'
import yaml, os
d = yaml.safe_load(open(os.environ['MANIFEST_PATH']))
print('true' if d.get('claude_md', {}).get('portable') else 'false')
PYEOF
}

yaml_get_idempotency() {
  MANIFEST_PATH="$MANIFEST" python3 - <<'PYEOF'
import yaml, os
d = yaml.safe_load(open(os.environ['MANIFEST_PATH']))
print(d.get('idempotency', 'skip'))
PYEOF
}

yaml_validate_manifest() {
  MANIFEST_PATH="$MANIFEST" python3 - <<'PYEOF'
import yaml, os, sys
try:
  d = yaml.safe_load(open(os.environ['MANIFEST_PATH']))
  issues = []
  for section in ['skills', 'commands', 'agents', 'scripts']:
    for i, entry in enumerate(d.get(section, [])):
      if isinstance(entry, dict):
        if not entry.get('name'):
          issues.append(f"  WARN: {section}[{i}] missing 'name' field")
  for i, entry in enumerate(d.get('plugins', [])):
    if not entry.get('id') or not entry.get('marketplace'):
      issues.append(f"  WARN: plugins[{i}] missing 'id' or 'marketplace'")
  if issues:
    for issue in issues:
      print(issue, file=sys.stderr)
  sys.exit(0 if not issues else 0)  # WARN is non-blocking
except Exception as e:
  print(f"  ERROR: manifest validation failed: {e}", file=sys.stderr)
  sys.exit(1)
PYEOF
}

yaml_validate_manifest || { echo "ERROR: manifest validation failed" >&2; exit 1; }
IDEMPOTENCY="$(yaml_get_idempotency)" || { echo "ERROR: failed to parse manifest" >&2; exit 1; }

# --- SHA-256 helpers ---
file_sha256() {
  "${SHA256_CMD[@]}" "$1" | cut -c1-64
}

# -print0 / sort -z / xargs -0 handle filenames with spaces (C2); -r avoids stdin-block on empty dirs (I1)
dir_sha256() {
  local hashes
  if ! hashes=$(find "$1" -type f -print0 | sort -z | xargs -0 -r "${SHA256_CMD[@]}"); then
    return 1
  fi
  if [[ -z "$hashes" ]]; then
    printf 'empty-dir'
  else
    printf '%s' "$hashes" | "${SHA256_CMD[@]}" | cut -c1-64
  fi
}

# --- install_file <repo_path> <dest_path> <label> ---
install_file() {
  local src="$1" dest="$2" label="$3"
  if [[ ! -f "$src" ]]; then
    echo "  WARN: source not found: $src" >&2
    (( CNT_MISSING++ )) || true
    return
  fi
  if [[ ! -f "$dest" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  [MISSING]  $label"
      (( CNT_MISSING++ )) || true
    else
      mkdir -p "$(dirname "$dest")"
      cp "$src" "$dest"
      echo "  [INSTALLED] $label"
      (( CNT_UPDATED++ )) || true
    fi
    return
  fi
  local src_hash dest_hash
  src_hash="$(file_sha256 "$src")"
  dest_hash="$(file_sha256 "$dest")"
  if [[ "$src_hash" == "$dest_hash" ]]; then
    echo "  [OK]       $label"
    (( CNT_OK++ )) || true
    return
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [STALE]    $label"
    (( CNT_MISSING++ )) || true
  elif [[ $FORCE -eq 1 ]] || [[ "$IDEMPOTENCY" == "overwrite" ]]; then
    cp "$src" "$dest"
    echo "  [UPDATED]  $label"
    (( CNT_UPDATED++ )) || true
  elif [[ "$IDEMPOTENCY" == "skip" ]]; then
    echo "  [SKIP]     $label (SHA-256 differs; use --force to overwrite)"
    (( CNT_OK++ )) || true
  else
    read -rp "  Overwrite $label? [y/N] " ans
    if [[ "${ans,,}" == "y" ]]; then
      cp "$src" "$dest"
      echo "  [UPDATED]  $label"
      (( CNT_UPDATED++ )) || true
    else
      echo "  [SKIPPED]  $label"
      (( CNT_OK++ )) || true
    fi
  fi
}

# Atomic dir replace: copy to temp first, then swap — rolls back on copy failure (C4)
_overwrite_dir() {
  local src="$1" dest="$2" label="$3"
  local dest_parent name tmp
  dest_parent="$(dirname "$dest")"
  name="$(basename "$dest")"
  tmp="$(mktemp -d "$dest_parent/.sync-XXXXXX")"
  if ! cp -rp "$src" "$tmp/$name"; then
    rm -rf "$tmp"
    echo "  ERROR: copy failed for $label/" >&2
    (( CNT_MISSING++ )) || true
    return
  fi
  rm -rf "$dest"
  if mv "$tmp/$name" "$dest"; then
    rmdir "$tmp" 2>/dev/null || true
    echo "  [UPDATED]  $label/"
    (( CNT_UPDATED++ )) || true
  else
    echo "  ERROR: move failed for $label/ — backup preserved at $tmp/$name" >&2
    (( CNT_MISSING++ )) || true
  fi
}

# --- install_dir <repo_path> <dest_path> <label> ---
install_dir() {
  local src="$1" dest="$2" label="$3"
  if [[ ! -d "$src" ]]; then
    echo "  WARN: source dir not found: $src" >&2
    (( CNT_MISSING++ )) || true
    return
  fi
  if [[ ! -d "$dest" ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  [MISSING]  $label/"
      (( CNT_MISSING++ )) || true
    else
      if ! cp -rp "$src" "$dest"; then
        echo "  ERROR: copy failed for $label/" >&2
        (( CNT_MISSING++ )) || true
      else
        echo "  [INSTALLED] $label/"
        (( CNT_UPDATED++ )) || true
      fi
    fi
    return
  fi
  local src_hash dest_hash
  src_hash="$(dir_sha256 "$src")"
  dest_hash="$(dir_sha256 "$dest")"
  if [[ "$src_hash" == "$dest_hash" ]]; then
    echo "  [OK]       $label/"
    (( CNT_OK++ )) || true
    return
  fi
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [STALE]    $label/"
    (( CNT_MISSING++ )) || true
  elif [[ $FORCE -eq 1 ]] || [[ "$IDEMPOTENCY" == "overwrite" ]]; then
    _overwrite_dir "$src" "$dest" "$label"
  elif [[ "$IDEMPOTENCY" == "skip" ]]; then
    echo "  [SKIP]     $label/ (SHA-256 differs; use --force to overwrite)"
    (( CNT_OK++ )) || true
  else
    read -rp "  Overwrite $label/? [y/N] " ans
    if [[ "${ans,,}" == "y" ]]; then
      _overwrite_dir "$src" "$dest" "$label"
    else
      echo "  [SKIPPED]  $label/"
      (( CNT_OK++ )) || true
    fi
  fi
}

# --- install_plugin <id> <marketplace> ---
install_plugin() {
  local id="$1" marketplace="$2" key="${1}@${2}"
  local plugins_json="$CLAUDE_DIR/plugins/installed_plugins.json"

  if [[ -f "$plugins_json" ]]; then
    local is_installed
    is_installed=$(PLUGINS_JSON="$plugins_json" PLUGIN_KEY="$key" python3 - <<'PYEOF'
import json, os
data = json.load(open(os.environ['PLUGINS_JSON']))
plugins = data.get('plugins', {})
entry = plugins.get(os.environ['PLUGIN_KEY'], [])
user_scoped = any(e.get('scope') == 'user' for e in entry)
print('true' if user_scoped else 'false')
PYEOF
) || { echo "  WARN: could not parse $plugins_json — treating plugin as missing" >&2; is_installed="false"; }
    if [[ "$is_installed" == "true" ]]; then
      echo "  [OK]       plugin:$key"
      (( CNT_OK++ )) || true
      return
    fi
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  [MISSING_PLUGIN] $key"
    (( CNT_MISSING_PLUGIN++ )) || true
    return
  fi

  if ! command -v claude >/dev/null 2>&1; then
    echo "  WARN: claude CLI not found — skipping plugin install for $key" >&2
    (( CNT_MISSING_PLUGIN++ )) || true
    return
  fi

  echo "  Installing plugin $key ..."
  local attempt=1 max_attempts=3 backoff=1
  while [[ $attempt -le $max_attempts ]]; do
    if claude plugin install "$id" --marketplace "$marketplace"; then
      echo "  [INSTALLED] plugin:$key"
      (( CNT_UPDATED++ )) || true
      return
    fi
    if [[ $attempt -lt $max_attempts ]]; then
      echo "  WARN: plugin install attempt $attempt/$max_attempts failed; retrying in ${backoff}s..." >&2
      sleep "$backoff"
      backoff=$((backoff * 2))
      (( attempt++ ))
    else
      (( attempt++ ))
    fi
  done
  echo "  WARN: plugin install failed after $max_attempts attempts for $key" >&2
  (( CNT_MISSING_PLUGIN++ )) || true
}

# --- scan_local_only: report ~/.claude/<type>/ entries absent from manifest ---
scan_local_only() {
  local type="$1" dest_dir="$2"
  [[ -d "$dest_dir" ]] || return 0

  local manifest_names
  manifest_names=$(yaml_get_names "$type") || { echo "  WARN: manifest parse failed for $type scan" >&2; return; }

  # skills are dirs at depth 1; commands may have one subdir level; agents/scripts are flat files
  local find_args=()
  if [[ "$type" == "skills" ]]; then
    find_args=(-maxdepth 1 -mindepth 1 -type d)
  elif [[ "$type" == "commands" ]]; then
    find_args=(-maxdepth 2 -mindepth 1 -type f)
  else
    find_args=(-maxdepth 1 -mindepth 1 -type f)
  fi

  while IFS= read -r entry; do
    local rel="${entry#"$dest_dir"/}"
    if ! printf '%s\n' "$manifest_names" | grep -qx "$rel"; then
      echo "  [LOCAL_ONLY] $type/$rel"
      (( CNT_LOCAL_ONLY++ )) || true
    fi
  done < <(find "$dest_dir" "${find_args[@]}" | sort)
}

# --- main ---
echo "=== Claude artifact sync ==="
echo "repo:   $REPO_DIR"
echo "target: $CLAUDE_DIR"
echo "mode:   $([ $DRY_RUN -eq 1 ] && echo dry-run || echo install) $([ $FORCE -eq 1 ] && echo +force)"
echo ""

echo "--- skills ---"
names=$(yaml_get_names skills) || { echo "ERROR: manifest parse failed for skills" >&2; exit 1; }
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  install_dir "$REPO_DIR/.claude/skills/$name" "$CLAUDE_DIR/skills/$name" "skills/$name"
done <<< "$names"

echo "--- commands ---"
names=$(yaml_get_names commands) || { echo "ERROR: manifest parse failed for commands" >&2; exit 1; }
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  src="$REPO_DIR/.claude/commands/$name"
  dest="$CLAUDE_DIR/commands/$name"
  if [[ -d "$src" ]]; then
    install_dir "$src" "$dest" "commands/$name"
  else
    install_file "$src" "$dest" "commands/$name"
  fi
done <<< "$names"

echo "--- agents ---"
names=$(yaml_get_names agents) || { echo "ERROR: manifest parse failed for agents" >&2; exit 1; }
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  install_file "$REPO_DIR/.claude/agents/$name" "$CLAUDE_DIR/agents/$name" "agents/$name"
done <<< "$names"

echo "--- scripts ---"
scripts=$(yaml_get_scripts) || { echo "ERROR: manifest parse failed for scripts" >&2; exit 1; }
while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  name="${entry%%|*}"
  executable="${entry##*|}"
  dest="$CLAUDE_DIR/scripts/$name"
  install_file "$REPO_DIR/.claude/scripts/$name" "$dest" "scripts/$name"
  if [[ "$executable" == "true" && -f "$dest" && $DRY_RUN -eq 0 ]]; then
    chmod +x "$dest"
  fi
done <<< "$scripts"

echo "--- claude_md ---"
portable=$(yaml_get_claude_md_portable) || { echo "ERROR: manifest parse failed for claude_md" >&2; exit 1; }
if [[ "$portable" == "true" ]]; then
  install_file "$REPO_DIR/.claude/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md" "CLAUDE.md"
else
  echo "  [SKIP]     CLAUDE.md (portable: false)"
fi

echo "--- plugins ---"
plugins=$(yaml_get_plugins) || { echo "ERROR: manifest parse failed for plugins" >&2; exit 1; }
while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  id="${entry%%|*}"
  marketplace="${entry##*|}"
  install_plugin "$id" "$marketplace"
done <<< "$plugins"

echo "--- local-only scan ---"
scan_local_only skills   "$CLAUDE_DIR/skills"
scan_local_only commands "$CLAUDE_DIR/commands"
scan_local_only agents   "$CLAUDE_DIR/agents"
scan_local_only scripts  "$CLAUDE_DIR/scripts"

echo ""
echo "=== summary ==="
echo "  OK:             $CNT_OK"
echo "  updated:        $CNT_UPDATED"
echo "  missing:        $CNT_MISSING"
echo "  local_only:     $CNT_LOCAL_ONLY"
echo "  missing_plugin: $CNT_MISSING_PLUGIN"
