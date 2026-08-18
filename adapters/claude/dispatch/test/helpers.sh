#!/usr/bin/env bash
# Shared assertions and fixtures for the dispatch test suite.

fail() {
  printf '    FAIL: %s\n' "$1" >&2
  TEST_FAILED=1
}

assert_eq() {
  local actual="$1" expected="$2" label="${3:-}"
  [ "$actual" = "$expected" ] || fail "${label:+$label: }expected '$expected', got '$actual'"
}

assert_contains() {
  local haystack="$1" needle="$2"
  case "$haystack" in
    *"$needle"*) ;;
    *) fail "expected to contain '$needle', got: $haystack" ;;
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

# mkrepo <path> [branch] - create a git repo with one commit
mkrepo() {
  local path="$1" branch="${2:-main}"
  mkdir -p "$path"
  git -C "$path" init -q -b "$branch"
  git -C "$path" config user.email test@example.com
  git -C "$path" config user.name "Test"
  git -C "$path" config commit.gpgsign false
  printf 'seed\n' > "$path/README.md"
  printf '.dispatch-argv\n' > "$path/.gitignore"
  git -C "$path" add -A
  git -C "$path" commit -qm "init"
}

# mkremote <path> - give an existing repo a bare origin with origin/HEAD set
mkremote() {
  local path="$1" bare="$1.git" branch
  branch="$(git -C "$path" branch --show-current)"
  git init -q --bare -b "$branch" "$bare"
  git -C "$path" remote add origin "$bare"
  git -C "$path" push -q -u origin HEAD
  git -C "$path" remote set-head origin -a >/dev/null 2>&1
}

run_test() {
  local name="$1"
  TEST_FAILED=0
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/dispatch-test.XXXXXX")"
  printf '  %s\n' "$name"
  "$name"
  TESTS_RUN=$((TESTS_RUN + 1))
  [ "$TEST_FAILED" -eq 0 ] || TESTS_FAILED=$((TESTS_FAILED + 1))
  rm -rf "$SANDBOX"
}
