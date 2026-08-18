#!/usr/bin/env bash

GIT_COMMIT_SKILL="$(cd "$ROOT/../../../skills/git-commit" && pwd)/SKILL.md"

test_git_commit_skill_has_valid_frontmatter() {
  assert_eq "$(head -1 "$GIT_COMMIT_SKILL")" "---" "first line of SKILL.md"
  assert_file_has "$GIT_COMMIT_SKILL" "name: git-commit"
  assert_file_has "$GIT_COMMIT_SKILL" "description:"
}

test_git_commit_skill_preserves_staged_intent() {
  assert_file_has "$GIT_COMMIT_SKILL" "Treat an existing staged set as user intent"
  assert_file_has "$GIT_COMMIT_SKILL" 'Do not use broad staging such as `git add -A`'
}

test_git_commit_skill_requires_explanatory_messages() {
  assert_file_has "$GIT_COMMIT_SKILL" "why the change exists"
  assert_file_has "$GIT_COMMIT_SKILL" "searchable or reproducible"
  assert_file_has "$GIT_COMMIT_SKILL" "Match the repository's established message style"
}

test_git_commit_skill_keeps_dangerous_actions_explicit() {
  assert_file_has "$GIT_COMMIT_SKILL" "bypass hooks"
  assert_file_has "$GIT_COMMIT_SKILL" "force-push"
  assert_file_has "$GIT_COMMIT_SKILL" "unless the user explicitly requested"
}

test_git_commit_skill_within_line_budget() {
  assert_max_lines "$GIT_COMMIT_SKILL" 120
}
