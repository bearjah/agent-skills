#!/usr/bin/env bash

setup_dispatched_worktree() {
  mkdir -p "$SANDBOX/code/org"
  mkdir -p "$SANDBOX/worktrees/r"
  mkrepo "$SANDBOX/code/org/r" main
  mkremote "$SANDBOX/code/org/r"
  git -C "$SANDBOX/code/org/r" worktree add -q -b dispatch/c \
    "$SANDBOX/worktrees/r/c" origin/main
}

test_cleanup_removes_a_clean_worktree() {
  setup_dispatched_worktree
  DISPATCH_SEARCH_GLOB="$SANDBOX/code/*" DISPATCH_WORKTREE_ROOT="$SANDBOX/worktrees" \
    "$ROOT/bin/dispatch-task.sh" --cleanup c --target r >/dev/null 2>&1 \
    || fail "cleanup of a clean worktree failed"
  [ ! -d "$SANDBOX/worktrees/r/c" ] || fail "worktree not removed"
}

test_cleanup_refuses_dirty_worktree() {
  setup_dispatched_worktree
  printf 'wip\n' >> "$SANDBOX/worktrees/r/c/README.md"
  local out
  out="$(DISPATCH_SEARCH_GLOB="$SANDBOX/code/*" DISPATCH_WORKTREE_ROOT="$SANDBOX/worktrees" \
    "$ROOT/bin/dispatch-task.sh" --cleanup c --target r 2>&1)" \
    && fail "expected refusal for dirty worktree"
  assert_contains "$out" "uncommitted changes"
  [ -d "$SANDBOX/worktrees/r/c" ] || fail "dirty worktree was removed anyway"
}

test_cleanup_force_removes_dirty_worktree() {
  setup_dispatched_worktree
  printf 'wip\n' >> "$SANDBOX/worktrees/r/c/README.md"
  DISPATCH_SEARCH_GLOB="$SANDBOX/code/*" DISPATCH_WORKTREE_ROOT="$SANDBOX/worktrees" \
    "$ROOT/bin/dispatch-task.sh" --cleanup c --target r --force >/dev/null 2>&1 \
    || fail "forced cleanup failed"
  [ ! -d "$SANDBOX/worktrees/r/c" ] || fail "worktree not removed with --force"
}

test_cleanup_refuses_unmerged_commits() {
  setup_dispatched_worktree
  printf 'work\n' >> "$SANDBOX/worktrees/r/c/README.md"
  git -C "$SANDBOX/worktrees/r/c" commit -qam "work"
  local out
  out="$(DISPATCH_SEARCH_GLOB="$SANDBOX/code/*" DISPATCH_WORKTREE_ROOT="$SANDBOX/worktrees" \
    "$ROOT/bin/dispatch-task.sh" --cleanup c --target r 2>&1)" \
    && fail "expected refusal for unmerged commits"
  assert_contains "$out" "not in origin/main"
}
