#!/usr/bin/env bash
# Runs every test_* function defined in test/test_*.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT
# shellcheck source=test/helpers.sh
source "$ROOT/test/helpers.sh"

TESTS_RUN=0
TESTS_FAILED=0

for f in "$ROOT"/test/test_*.sh; do
  # shellcheck source=/dev/null
  source "$f"
done

while read -r fn; do
  run_test "$fn"
done < <(declare -F | awk '{print $3}' | grep '^test_' | sort)

printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
