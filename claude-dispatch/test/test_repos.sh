#!/usr/bin/env bash
# shellcheck source=lib/repos.sh
source "$ROOT/lib/repos.sh"

test_resolve_repo_finds_by_name() {
  mkdir -p "$SANDBOX/code/org"
  mkrepo "$SANDBOX/code/org/minimos"
  # The override must sit inside the command substitution: a prefix on
  # assert_eq would be applied only after its arguments were expanded.
  local got
  got="$(DISPATCH_SEARCH_GLOB="$SANDBOX/code/*" resolve_repo minimos)"
  assert_eq "$got" "$SANDBOX/code/org/minimos" "by name"
}

test_resolve_repo_accepts_absolute_path() {
  mkrepo "$SANDBOX/elsewhere"
  assert_eq "$(resolve_repo "$SANDBOX/elsewhere")" "$SANDBOX/elsewhere" "abs path"
}

test_resolve_repo_rejects_unknown_name() {
  local out
  out="$(DISPATCH_SEARCH_GLOB="$SANDBOX/code/*" resolve_repo nosuch 2>&1)" && \
    fail "expected failure for unknown repo"
  assert_contains "$out" "no repo named"
}

test_resolve_repo_rejects_ambiguous_name() {
  mkdir -p "$SANDBOX/code/a" "$SANDBOX/code/b"
  mkrepo "$SANDBOX/code/a/images"
  mkrepo "$SANDBOX/code/b/images"
  local out
  out="$(DISPATCH_SEARCH_GLOB="$SANDBOX/code/*" resolve_repo images 2>&1)" && \
    fail "expected failure for ambiguous repo"
  assert_contains "$out" "ambiguous"
}

test_resolve_repo_rejects_non_git_dir() {
  mkdir -p "$SANDBOX/code/org/notarepo"
  local out
  out="$(DISPATCH_SEARCH_GLOB="$SANDBOX/code/*" resolve_repo notarepo 2>&1)" && \
    fail "expected failure for non-git dir"
  assert_contains "$out" "no repo named"
}

test_detect_base_uses_origin_head() {
  mkrepo "$SANDBOX/r" main
  mkremote "$SANDBOX/r"
  assert_eq "$(detect_base "$SANDBOX/r")" "origin/main" "origin/HEAD"
}

test_detect_base_falls_back_to_origin_master() {
  mkrepo "$SANDBOX/r" master
  mkremote "$SANDBOX/r"
  git -C "$SANDBOX/r" symbolic-ref -d refs/remotes/origin/HEAD
  assert_eq "$(detect_base "$SANDBOX/r")" "origin/master" "master fallback"
}

test_detect_base_fails_without_remote() {
  mkrepo "$SANDBOX/r" main
  local out
  out="$(detect_base "$SANDBOX/r" 2>&1)" && fail "expected failure with no remote"
  assert_contains "$out" "--base"
}
