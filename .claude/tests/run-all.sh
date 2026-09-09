#!/usr/bin/env bash
# Runs every *.test.sh under .claude/tests/scripts/.
#
# Each suite is self-contained and sandboxes itself (HOME redirected to a
# mktemp dir), so this never touches the real ~/.claude/.
#
# Exit 0 when every suite passes, 1 when any fails.
#
# Usage: bash .claude/tests/run-all.sh
set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$TESTS_DIR/scripts"

shopt -s nullglob
suites=("$SCRIPTS_DIR"/*.test.sh)
shopt -u nullglob

if [[ ${#suites[@]} -eq 0 ]]; then
  echo "No test suites found in $SCRIPTS_DIR" >&2
  exit 1
fi

total=0
failed=0
failed_names=()

for suite in "${suites[@]}"; do
  name="$(basename "$suite")"
  total=$((total + 1))
  printf '\n\033[1m=== %s ===\033[0m\n' "$name"
  if bash "$suite"; then
    printf '\033[32m--- %s OK\033[0m\n' "$name"
  else
    printf '\033[31m--- %s FAILED\033[0m\n' "$name"
    failed=$((failed + 1))
    failed_names+=("$name")
  fi
done

printf '\n\033[1m=== Summary ===\033[0m\n'
printf '  suites run:    %d\n' "$total"
printf '  suites passed: %d\n' "$((total - failed))"
printf '  suites failed: %d\n' "$failed"

if [[ $failed -gt 0 ]]; then
  printf '\n\033[31mFAILED:\033[0m\n'
  for n in "${failed_names[@]}"; do
    printf '  - %s\n' "$n"
  done
  exit 1
fi

printf '\n\033[32mAll suites passed.\033[0m\n'
