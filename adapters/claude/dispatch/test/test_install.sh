#!/usr/bin/env bash
# The Claude installer: what it links into ~/.claude and what it refuses.

test_install_links_the_git_commit_skill() {
  local home skill_dir
  home="$SANDBOX/home"
  skill_dir="$(cd "$ROOT/../../../skills/git-commit" && pwd)"
  mkdir -p "$home"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  [ -L "$home/.claude/skills/git-commit" ] || fail "git-commit symlink missing"
  assert_eq "$(readlink "$home/.claude/skills/git-commit")" \
    "$skill_dir" "git-commit link target"
  assert_file_has "$home/.claude/skills/git-commit/SKILL.md" "name: git-commit"
}

test_install_reports_what_it_linked() {
  local home out
  home="$SANDBOX/home"
  mkdir -p "$home"
  out="$(HOME="$home" bash "$ROOT/install.sh")"
  assert_contains "$out" "$home/.claude/scripts/dispatch-task.sh"
  assert_contains "$out" "$home/.claude/commands/dispatch.md"
  assert_contains "$out" "$home/.claude/skills/git-commit"
}

# `ln -sfn` would nest the link inside a real directory, leaving the skill
# undiscoverable at the path it reports. Refuse before anything is linked.
test_install_refuses_a_real_directory_at_git_commit_path() {
  local home rc
  home="$SANDBOX/home"
  mkdir -p "$home/.claude/skills/git-commit"
  rc=0
  HOME="$home" bash "$ROOT/install.sh" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "expected non-zero exit for a real git-commit dir"
  [ ! -e "$home/.claude/skills/git-commit/git-commit" ] \
    || fail "installer nested the link inside the pre-existing directory"
  [ ! -e "$home/.claude/scripts/dispatch-task.sh" ] \
    || fail "a rejected install still linked the dispatch script"
}

# An earlier version linked a finalize-work skill that no longer exists. After
# an update that link points at nothing, so the installer clears it.
test_install_removes_the_link_to_the_retired_finalize_work_skill() {
  local home
  home="$SANDBOX/home"
  mkdir -p "$home/.claude/skills"
  ln -s "$SANDBOX/gone/skills/finalize-work" "$home/.claude/skills/finalize-work"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  [ ! -L "$home/.claude/skills/finalize-work" ] \
    || fail "the dead finalize-work link was left behind"
}

# A finalize-work skill of the user's own is not ours to delete.
test_install_keeps_a_finalize_work_skill_that_still_resolves() {
  local home
  home="$SANDBOX/home"
  mkdir -p "$home/.claude/skills/finalize-work"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  [ -d "$home/.claude/skills/finalize-work" ] \
    || fail "installer removed a finalize-work skill it did not own"
}

test_codex_install_removes_the_link_to_the_retired_finalize_work_skill() {
  local home
  home="$SANDBOX/home"
  mkdir -p "$home/.codex/skills"
  ln -s "$SANDBOX/gone/skills/finalize-work" "$home/.codex/skills/finalize-work"
  HOME="$home" AGENT_DOCS_ROOT="$SANDBOX/docs" \
    bash "$ROOT/../../codex/dispatch/install.sh" >/dev/null
  [ ! -L "$home/.codex/skills/finalize-work" ] \
    || fail "the dead finalize-work link was left behind"
}
