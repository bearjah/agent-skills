#!/usr/bin/env bash
# The installers: what they link into the agent's home and what they clear.

test_install_reports_what_it_linked() {
  local home out
  home="$SANDBOX/home"
  mkdir -p "$home"
  out="$(HOME="$home" bash "$ROOT/install.sh")"
  assert_contains "$out" "$home/.claude/scripts/dispatch-task.sh"
  assert_contains "$out" "$home/.claude/commands/dispatch.md"
  [ -L "$home/.claude/scripts/dispatch-task.sh" ] || fail "dispatch script link missing"
  [ -L "$home/.claude/commands/dispatch.md" ] || fail "dispatch command link missing"
}

# Earlier versions linked finalize-work and git-commit skills that no longer
# exist. After an update those links point at nothing, so the installer clears
# them.
test_install_removes_links_to_retired_skills() {
  local home skill
  home="$SANDBOX/home"
  mkdir -p "$home/.claude/skills"
  for skill in finalize-work git-commit; do
    ln -s "$SANDBOX/gone/skills/$skill" "$home/.claude/skills/$skill"
  done
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  for skill in finalize-work git-commit; do
    [ ! -L "$home/.claude/skills/$skill" ] || fail "the dead $skill link was left behind"
  done
}

# A skill of the user's own under one of those names is not ours to delete.
test_install_keeps_a_same_named_skill_that_still_resolves() {
  local home skill
  home="$SANDBOX/home"
  mkdir -p "$home/.claude/skills/finalize-work" "$home/.claude/skills/git-commit"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null || fail "install failed beside the user's own skills"
  for skill in finalize-work git-commit; do
    [ -d "$home/.claude/skills/$skill" ] || fail "installer removed a $skill skill it did not own"
  done
}

test_codex_install_removes_links_to_retired_skills() {
  local home skill
  home="$SANDBOX/home"
  mkdir -p "$home/.codex/skills"
  for skill in finalize-work git-commit; do
    ln -s "$SANDBOX/gone/skills/$skill" "$home/.codex/skills/$skill"
  done
  HOME="$home" AGENT_DOCS_ROOT="$SANDBOX/docs" \
    bash "$ROOT/../../codex/dispatch/install.sh" >/dev/null
  for skill in finalize-work git-commit; do
    [ ! -L "$home/.codex/skills/$skill" ] || fail "the dead $skill link was left behind"
  done
}
