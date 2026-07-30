#!/usr/bin/env bash
# shellcheck source=lib/worktree.sh
source "$ROOT/lib/worktree.sh"

test_worktree_path_is_sibling_of_repo() {
  assert_eq "$(worktree_path /home/u/code/org/minimos fixauth)" \
            "/home/u/code/org/minimos-wt-fixauth" "sibling layout"
}

test_create_worktree_uses_base_and_branch() {
  mkrepo "$SANDBOX/r" main
  mkremote "$SANDBOX/r"
  local wt
  wt="$(create_worktree "$SANDBOX/r" fixauth origin/main)"
  assert_eq "$wt" "$SANDBOX/r-wt-fixauth" "worktree path"
  assert_eq "$(git -C "$wt" branch --show-current)" "dispatch/fixauth" "branch name"
  assert_eq "$(git -C "$wt" rev-parse HEAD)" \
            "$(git -C "$SANDBOX/r" rev-parse origin/main)" "based on origin/main"
}

test_worktree_is_dirty_detects_changes() {
  mkrepo "$SANDBOX/r" main
  mkremote "$SANDBOX/r"
  local wt
  wt="$(create_worktree "$SANDBOX/r" d origin/main)"
  worktree_is_dirty "$wt" && fail "clean worktree reported dirty"
  printf 'change\n' >> "$wt/README.md"
  worktree_is_dirty "$wt" || fail "dirty worktree reported clean"
}

test_worktree_has_unmerged_detects_commits() {
  mkrepo "$SANDBOX/r" main
  mkremote "$SANDBOX/r"
  local wt
  wt="$(create_worktree "$SANDBOX/r" u origin/main)"
  worktree_has_unmerged "$wt" origin/main && fail "fresh worktree reported unmerged"
  printf 'change\n' >> "$wt/README.md"
  git -C "$wt" commit -qam "work"
  worktree_has_unmerged "$wt" origin/main || fail "committed work reported merged"
}

test_remove_worktree_deletes_dir_and_branch() {
  mkrepo "$SANDBOX/r" main
  mkremote "$SANDBOX/r"
  create_worktree "$SANDBOX/r" gone origin/main >/dev/null
  remove_worktree "$SANDBOX/r" gone origin/main 0 || fail "remove failed"
  [ ! -d "$SANDBOX/r-wt-gone" ] || fail "worktree dir still present"
  git -C "$SANDBOX/r" rev-parse --verify --quiet refs/heads/dispatch/gone >/dev/null 2>&1 \
    && fail "branch still present"
}
