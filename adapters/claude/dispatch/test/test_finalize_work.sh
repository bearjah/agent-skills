#!/usr/bin/env bash
# The finalize-work skill: its structure, its install link, and the locate
# recipe it tells the reader to run.

CORE_SKILL_DIR="$(cd "$ROOT/../../../skills/finalize-work" && pwd)"
SKILL="$CORE_SKILL_DIR/SKILL.md"

# The locate recipe is executable, so test it by running the exact lines the
# skill publishes rather than a copy that could drift from them.
locate_recipe() {
  awk '/^# locate:/{f=1} f && /^```$/{exit} f' "$SKILL"
}

# run_locate <dir> - run the recipe in <dir> with HOME pinned to the sandbox.
# Prints its output; returns its exit status.
run_locate() {
  local dir="$1" recipe
  recipe="$(locate_recipe)"
  (cd "$dir" && HOME="$SANDBOX" bash -c "$recipe" 2>&1)
}

worktree_dir() {
  printf '%s/.claude/worktrees/%s/%s\n' "$SANDBOX" "$1" "$2"
}

# mkdispatch <org> <repo> <slug> - a repo plus a dispatch worktree beside it
mkdispatch() {
  local org="$1" repo="$2" slug="$3" root="$SANDBOX/code/$1/$2" wt
  wt="$(worktree_dir "$repo" "$slug")"
  mkdir -p "$SANDBOX/code/$org"
  mkdir -p "$(dirname "$wt")"
  mkrepo "$root" main
  git -C "$root" worktree add -q -b "dispatch/$slug" "$wt"
}

test_finalize_work_frontmatter() {
  assert_eq "$(head -1 "$SKILL")" "---" "first line of SKILL.md"
  assert_file_has "$SKILL" "name: finalize-work"
  assert_file_has "$SKILL" "description:"
}

test_finalize_work_description_carries_the_real_trigger_phrases() {
  local p
  for p in "finalize this work" "wrap up" "ready to close this session" \
           "clean up before I close this"; do
    assert_file_has "$SKILL" "$p"
  done
}

test_finalize_work_has_all_three_phases() {
  local s
  for s in "## 0. Locate the dispatch" "## Phase 1" "## Phase 2" "## Phase 3" \
           "## Authority"; do
    assert_file_has "$SKILL" "$s"
  done
}

# The two failures observed in baseline runs without the skill: every run
# declared the worktree disposable without naming the removal command, and runs
# on a research-only work item never queried GitHub at all. Pin both.
test_finalize_work_names_the_cleanup_command() {
  assert_file_has "$SKILL" "dispatch-task.sh --cleanup <slug> --target <repo>"
}

test_finalize_work_requires_pr_state_from_gh() {
  assert_file_has "$SKILL" "gh pr view"
  assert_file_has "$SKILL" "gh pr list"
}

test_finalize_work_verdict_contract_has_every_slot() {
  local s
  for s in "committed:" "PR state:" "left undone:" "for you:" "verdict:"; do
    assert_file_has "$SKILL" "$s"
  done
}

test_finalize_work_refuses_to_destroy() {
  assert_file_has "$SKILL" "Delete or move any file"
  assert_file_has "$SKILL" "Remove a worktree or delete a branch"
}

test_finalize_work_within_line_budget() {
  assert_max_lines "$SKILL" 170
}

# Both pinned from dry runs against real work items, where the first draft of the
# recipe was wrong. A brand-new work item folder is untracked, and `git commit --
# <path>` cannot reach an untracked path -- it exits non-zero on a pathspec that
# matches nothing known to git.
test_finalize_work_stages_before_the_pathspec_commit() {
  assert_file_has "$SKILL" 'git -C "$agent_docs_root" add <category>/<item>'
}

test_finalize_work_uses_the_configured_docs_root() {
  assert_file_has "$SKILL" 'AGENT_DOCS_ROOT:-$HOME/docs'
  assert_file_has "$SKILL" '$agent_docs_root/designs/'
  assert_file_has "$SKILL" '$agent_docs_root/reviews/'
}

# A cross-repo dispatch can hold a second worktree under a slug of its own, which
# the single-slug glob in step 0 cannot see. One such worktree held an unpushed
# commit that existed on no other machine.
test_finalize_work_cross_checks_for_other_worktrees() {
  assert_file_has "$SKILL" "worktrees/[a-z0-9._-]+/[a-z0-9-]+"
}

test_locate_identifies_a_dispatch_worktree() {
  mkdispatch org r slugone
  local out
  out="$(run_locate "$(worktree_dir r slugone)")" \
    || fail "locate refused a real dispatch worktree"
  assert_contains "$out" "repo=r"
  assert_contains "$out" "slug=slugone"
  assert_contains "$out" "branch=dispatch/slugone"
  assert_contains "$out" "$(worktree_dir r slugone)"
}

test_locate_works_from_a_subdirectory() {
  mkdispatch org r slugone
  mkdir -p "$(worktree_dir r slugone)/deep/nested"
  local out
  out="$(run_locate "$(worktree_dir r slugone)/deep/nested")" \
    || fail "locate refused a subdirectory of a dispatch worktree"
  assert_contains "$out" "slug=slugone"
}

test_locate_refuses_a_plain_checkout() {
  mkdispatch org r slugone
  local out
  out="$(run_locate "$SANDBOX/code/org/r")" \
    && fail "locate accepted a plain checkout"
  assert_contains "$out" "not a dispatch worktree"
}

# Sessions rename the dispatch branch before opening a PR, so the layout -- not
# the branch name -- has to be what identifies the worktree.
test_locate_survives_a_renamed_branch() {
  mkdispatch org r slugone
  git -C "$(worktree_dir r slugone)" checkout -q -b renamed-for-the-pr
  local out
  out="$(run_locate "$(worktree_dir r slugone)")" \
    || fail "locate refused a worktree whose branch was renamed"
  assert_contains "$out" "slug=slugone"
  assert_contains "$out" "branch=renamed-for-the-pr"
}

# A cross-repo dispatch needs one --target per worktree it created.
test_locate_lists_every_target_of_the_dispatch() {
  mkdispatch org r shared
  mkdispatch org2 other shared
  local out
  out="$(run_locate "$(worktree_dir r shared)")" || fail "locate failed"
  assert_contains "$out" "$(worktree_dir r shared)"
  assert_contains "$out" "$(worktree_dir other shared)"
}

test_install_links_the_skill() {
  local home
  home="$SANDBOX/home"
  mkdir -p "$home"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  [ -L "$home/.claude/skills/finalize-work" ] || fail "skill symlink missing"
  assert_eq "$(readlink "$home/.claude/skills/finalize-work")" \
    "$CORE_SKILL_DIR" "skill link target"
  assert_file_has "$home/.claude/skills/finalize-work/SKILL.md" "name: finalize-work"
}

test_install_reports_the_skill_link() {
  local home out
  home="$SANDBOX/home"
  mkdir -p "$home"
  out="$(HOME="$home" bash "$ROOT/install.sh")"
  assert_contains "$out" "$home/.claude/skills/finalize-work"
}

# `ln -sfn` would nest the link inside a real directory, leaving the skill
# undiscoverable at the path it reports. Refuse before anything is linked.
test_install_refuses_a_real_directory_at_the_skill_path() {
  local home rc
  home="$SANDBOX/home"
  mkdir -p "$home/.claude/skills/finalize-work"
  rc=0
  HOME="$home" bash "$ROOT/install.sh" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "expected non-zero exit for a real dir at the skill path"
  [ ! -e "$home/.claude/skills/finalize-work/finalize-work" ] \
    || fail "installer nested the link inside the pre-existing directory"
  [ ! -e "$home/.claude/scripts/dispatch-task.sh" ] \
    || fail "a rejected install still linked the dispatch script"
}
