#!/usr/bin/env bash
# The Claude home setup: global instructions, the agents they route work to,
# and the plugin whose skills they call.

HOME_SETUP="$(cd "$ROOT/../home" && pwd)"

install_home() {
  HOME="$1" bash "$HOME_SETUP/install.sh"
}

test_home_install_links_the_instructions_and_agents() {
  local home="$SANDBOX/home" agent
  mkdir -p "$home"
  install_home "$home" >/dev/null || fail "install failed on an empty home"
  assert_eq "$(readlink "$home/.claude/CLAUDE.md")" "$HOME_SETUP/CLAUDE.md" "instructions link"
  for agent in scout runner planner implementer; do
    assert_eq "$(readlink "$home/.claude/agents/$agent.md")" \
      "$HOME_SETUP/agents/$agent.md" "$agent link"
  done
}

# Instructions someone already wrote are theirs; the installer must not
# overwrite them, and must not half-install around them either.
test_home_install_refuses_different_existing_instructions() {
  local home="$SANDBOX/home" rc=0
  mkdir -p "$home/.claude"
  printf 'my own rules\n' > "$home/.claude/CLAUDE.md"
  install_home "$home" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "expected refusal when different instructions exist"
  assert_eq "$(cat "$home/.claude/CLAUDE.md")" "my own rules" "existing instructions"
  [ ! -e "$home/.claude/agents/scout.md" ] || fail "a refused install still linked an agent"
  [ ! -e "$home/.claude/settings.json" ] || fail "a refused install still wrote settings"
}

test_home_install_refuses_a_different_existing_agent() {
  local home="$SANDBOX/home" rc=0
  mkdir -p "$home/.claude/agents"
  printf 'my own scout\n' > "$home/.claude/agents/scout.md"
  install_home "$home" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "expected refusal when a different agent exists"
  assert_eq "$(cat "$home/.claude/agents/scout.md")" "my own scout" "existing agent"
  [ ! -e "$home/.claude/CLAUDE.md" ] || fail "a refused install still linked the instructions"
}

# The machine the setup was first written on holds identical plain copies.
# Those become links, so later edits land in the repository.
test_home_install_replaces_identical_copies_with_links() {
  local home="$SANDBOX/home"
  mkdir -p "$home/.claude/agents"
  cp "$HOME_SETUP/CLAUDE.md" "$home/.claude/CLAUDE.md"
  cp "$HOME_SETUP/agents/scout.md" "$home/.claude/agents/scout.md"
  install_home "$home" >/dev/null || fail "install failed over identical copies"
  [ -L "$home/.claude/CLAUDE.md" ] || fail "identical instructions were not linked"
  [ -L "$home/.claude/agents/scout.md" ] || fail "identical agent was not linked"
}

test_home_install_leaves_other_agents_alone() {
  local home="$SANDBOX/home"
  mkdir -p "$home/.claude/agents"
  printf 'mine\n' > "$home/.claude/agents/other.md"
  install_home "$home" >/dev/null
  assert_eq "$(cat "$home/.claude/agents/other.md")" "mine" "unrelated agent"
}

test_home_install_enables_the_skills_plugin() {
  local home="$SANDBOX/home" settings
  mkdir -p "$home"
  install_home "$home" >/dev/null
  settings="$home/.claude/settings.json"
  assert_eq "$(jq -r '.enabledPlugins["agent-skills@addy-agent-skills"]' "$settings")" \
    "true" "plugin enabled"
  assert_eq "$(jq -r '.extraKnownMarketplaces["addy-agent-skills"].source.url' "$settings")" \
    "https://github.com/addyosmani/agent-skills.git" "plugin source"
}

# Settings are personal: model, theme, permission mode. Only the plugin entries
# are added; everything already there stays, and no permission mode is set.
test_home_install_keeps_existing_settings() {
  local home="$SANDBOX/home" settings
  mkdir -p "$home/.claude"
  settings="$home/.claude/settings.json"
  printf '{"model":"sonnet","enabledPlugins":{"other@market":true}}\n' > "$settings"
  install_home "$home" >/dev/null
  assert_eq "$(jq -r '.model' "$settings")" "sonnet" "existing model"
  assert_eq "$(jq -r '.enabledPlugins["other@market"]' "$settings")" "true" "existing plugin"
  assert_eq "$(jq -r '.enabledPlugins["agent-skills@addy-agent-skills"]' "$settings")" \
    "true" "plugin enabled"
  assert_eq "$(jq -r '.permissions.defaultMode // "unset"' "$settings")" "unset" "permission mode"
}

test_home_install_refuses_settings_it_cannot_read() {
  local home="$SANDBOX/home" rc=0
  mkdir -p "$home/.claude"
  printf '{not json\n' > "$home/.claude/settings.json"
  install_home "$home" >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "expected refusal for unreadable settings"
  assert_eq "$(cat "$home/.claude/settings.json")" "{not json" "settings left as found"
  [ ! -e "$home/.claude/CLAUDE.md" ] || fail "a refused install still linked the instructions"
}

test_home_install_can_run_twice() {
  local home="$SANDBOX/home"
  mkdir -p "$home"
  install_home "$home" >/dev/null
  install_home "$home" >/dev/null || fail "second install failed"
  [ -L "$home/.claude/CLAUDE.md" ] || fail "instructions link lost on second install"
}

# The repository is public, so the shared instructions must not carry a
# machine path or a person's name.
test_home_setup_has_no_machine_paths() {
  if grep -rnE '/home/|/Users/' "$HOME_SETUP/CLAUDE.md" "$HOME_SETUP/agents"; then
    fail "the shared setup names a machine path"
  fi
}

# A machine with a setup its owner no longer wants: --replace installs this
# one, and keeps what was there in a backup folder instead of deleting it.
test_home_install_replace_backs_up_and_links() {
  local home="$SANDBOX/home" out backup
  mkdir -p "$home/.claude/agents"
  printf 'old rules\n' > "$home/.claude/CLAUDE.md"
  printf 'old scout\n' > "$home/.claude/agents/scout.md"
  out="$(HOME="$home" bash "$HOME_SETUP/install.sh" --replace)" || fail "--replace failed"
  [ -L "$home/.claude/CLAUDE.md" ] || fail "instructions were not replaced"
  [ -L "$home/.claude/agents/scout.md" ] || fail "agent was not replaced"
  backup="$(find "$home/.claude/backups" -mindepth 1 -maxdepth 1 -type d -name 'home-setup-*')"
  [ -n "$backup" ] || fail "no backup folder was created"
  assert_eq "$(cat "$backup/CLAUDE.md")" "old rules" "backed-up instructions"
  assert_eq "$(cat "$backup/agents/scout.md")" "old scout" "backed-up agent"
  assert_contains "$out" "$backup"
}

test_home_install_replace_makes_no_backup_when_nothing_differs() {
  local home="$SANDBOX/home"
  mkdir -p "$home"
  HOME="$home" bash "$HOME_SETUP/install.sh" --replace >/dev/null || fail "--replace failed"
  [ ! -e "$home/.claude/backups" ] || fail "an empty backup folder was left behind"
}

test_home_install_replace_leaves_other_agents_and_settings() {
  local home="$SANDBOX/home"
  mkdir -p "$home/.claude/agents"
  printf 'old rules\n' > "$home/.claude/CLAUDE.md"
  printf 'mine\n' > "$home/.claude/agents/other.md"
  printf '{"model":"sonnet"}\n' > "$home/.claude/settings.json"
  HOME="$home" bash "$HOME_SETUP/install.sh" --replace >/dev/null
  assert_eq "$(cat "$home/.claude/agents/other.md")" "mine" "unrelated agent"
  assert_eq "$(jq -r '.model' "$home/.claude/settings.json")" "sonnet" "existing model"
}

test_home_install_refusal_names_the_replace_option() {
  local home="$SANDBOX/home" err
  mkdir -p "$home/.claude"
  printf 'old rules\n' > "$home/.claude/CLAUDE.md"
  err="$(HOME="$home" bash "$HOME_SETUP/install.sh" 2>&1 >/dev/null)" || true
  assert_contains "$err" "--replace"
}

test_home_install_rejects_an_unknown_option() {
  local home="$SANDBOX/home" rc=0
  mkdir -p "$home"
  HOME="$home" bash "$HOME_SETUP/install.sh" --force >/dev/null 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail "expected an unknown option to be rejected"
  [ ! -e "$home/.claude/CLAUDE.md" ] || fail "an unknown option still installed"
}
