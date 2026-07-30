#!/usr/bin/env bash
# Shared assertions for the promptify test suite.

fail() {
  printf '    FAIL: %s\n' "$1" >&2
  TEST_FAILED=1
}

assert_eq() {
  local actual="$1" expected="$2" label="${3:-}"
  [ "$actual" = "$expected" ] || fail "${label:+$label: }expected '$expected', got '$actual'"
}

assert_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  case "$haystack" in
    *"$needle"*) ;;
    *) fail "${label:+$label: }expected to contain '$needle', got: $haystack" ;;
  esac
}

# assert_file_has <file> <literal string>
assert_file_has() {
  local file="$1" needle="$2"
  if [ ! -f "$file" ]; then
    fail "missing file: $file"
    return
  fi
  grep -qF -- "$needle" "$file" || fail "$file: expected to contain '$needle'"
}

# assert_max_lines <file> <max>
assert_max_lines() {
  local file="$1" max="$2" n
  if [ ! -f "$file" ]; then
    fail "missing file: $file"
    return
  fi
  n="$(wc -l < "$file")"
  [ "$n" -le "$max" ] || fail "$file: $n lines exceeds budget of $max"
}

run_test() {
  local fn="$1"
  TEST_FAILED=0
  TESTS_RUN=$((TESTS_RUN + 1))
  printf '  %s\n' "$fn"
  "$fn"
  [ "$TEST_FAILED" -eq 0 ] || TESTS_FAILED=$((TESTS_FAILED + 1))
}
