#!/usr/bin/env bash
# Installer behavior, exercised against a throwaway HOME.

test_install_creates_symlinks() {
  local home
  home="$(mktemp -d)"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  [ -L "$home/.claude/skills/promptify" ] || fail "skill symlink missing"
  [ -L "$home/.claude/commands/p.md" ] || fail "command symlink missing"
  assert_eq "$(readlink "$home/.claude/skills/promptify")" "$ROOT" "skill link target"
  assert_eq "$(readlink "$home/.claude/commands/p.md")" "$ROOT/commands/p.md" "command link target"
  rm -rf "$home"
}

test_install_registers_the_trigger() {
  local home
  home="$(mktemp -d)"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  assert_file_has "$home/.claude/CLAUDE.md" "<!-- promptify:begin -->"
  assert_file_has "$home/.claude/CLAUDE.md" "<!-- promptify:end -->"
  assert_file_has "$home/.claude/CLAUDE.md" 'invoke the Skill tool with `skill: "promptify"`'
  rm -rf "$home"
}

test_install_is_idempotent() {
  local home n
  home="$(mktemp -d)"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  n="$(grep -cF '<!-- promptify:begin -->' "$home/.claude/CLAUDE.md")"
  assert_eq "$n" "1" "trigger block count after two installs"
  rm -rf "$home"
}

test_install_preserves_existing_claude_md() {
  local home n
  home="$(mktemp -d)"
  mkdir -p "$home/.claude"
  printf '# graphify\nkeep me\n' > "$home/.claude/CLAUDE.md"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  assert_file_has "$home/.claude/CLAUDE.md" "keep me"
  assert_file_has "$home/.claude/CLAUDE.md" "# graphify"
  n="$(grep -cF '<!-- promptify:begin -->' "$home/.claude/CLAUDE.md" || true)"
  assert_eq "$n" "1" "trigger block count after two installs on a pre-existing file"
  rm -rf "$home"
}

test_install_handles_claude_md_without_trailing_newline() {
  local home n
  home="$(mktemp -d)"
  mkdir -p "$home/.claude"
  printf 'no trailing newline' > "$home/.claude/CLAUDE.md"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  assert_file_has "$home/.claude/CLAUDE.md" "no trailing newline"
  n="$(grep -c '^<!-- promptify:begin -->' "$home/.claude/CLAUDE.md" || true)"
  assert_eq "$n" "1" "trigger block count, marker anchored at line start"
  rm -rf "$home"
}

test_install_aborts_on_unterminated_block() {
  local home rc before after
  home="$(mktemp -d)"
  mkdir -p "$home/.claude"
  printf '# notes\nkeep me\n<!-- promptify:begin -->\norphaned line that must survive\n' \
    > "$home/.claude/CLAUDE.md"
  before="$(cat "$home/.claude/CLAUDE.md")"
  rc=0
  HOME="$home" bash "$ROOT/install.sh" >/dev/null 2>/dev/null || rc=$?
  [ "$rc" -ne 0 ] || fail "expected non-zero exit for an unterminated promptify block, got 0"
  after="$(cat "$home/.claude/CLAUDE.md")"
  assert_eq "$after" "$before" "CLAUDE.md content must be unchanged after an aborted install"
  rm -rf "$home"
}

test_install_aborts_on_misordered_markers() {
  local home rc before after
  home="$(mktemp -d)"
  mkdir -p "$home/.claude"
  printf '%s\n' \
    '# graphify' \
    'keep me' \
    '<!-- promptify:end -->' \
    'stray body' \
    '<!-- promptify:begin -->' \
    > "$home/.claude/CLAUDE.md"
  before="$(cat "$home/.claude/CLAUDE.md")"
  rc=0
  HOME="$home" bash "$ROOT/install.sh" >/dev/null 2>/dev/null || rc=$?
  [ "$rc" -ne 0 ] || fail "expected non-zero exit for an end-before-begin marker, got 0"
  after="$(cat "$home/.claude/CLAUDE.md")"
  assert_eq "$after" "$before" "CLAUDE.md content must be unchanged after misordered markers are detected"
  rm -rf "$home"
}

test_install_does_not_strip_prose_mentioning_the_marker() {
  local home
  home="$(mktemp -d)"
  mkdir -p "$home/.claude"
  # Seed a REAL, well-formed block (so the strip path actually runs) followed
  # by a line that merely mentions the marker text as a substring, followed
  # by more content. An unanchored index()-based match would delete
  # everything from the mention onward; the anchored, whole-line match must
  # not.
  printf '%s\n' \
    '# graphify' \
    'keep me above' \
    '<!-- promptify:begin -->' \
    'an old promptify block body' \
    '<!-- promptify:end -->' \
    'Note: the literal marker text <!-- promptify:begin --> is just documentation here, not a real block.' \
    'keep me below the mention' \
    > "$home/.claude/CLAUDE.md"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  assert_file_has "$home/.claude/CLAUDE.md" "# graphify"
  assert_file_has "$home/.claude/CLAUDE.md" "keep me above"
  assert_file_has "$home/.claude/CLAUDE.md" "is just documentation here, not a real block."
  assert_file_has "$home/.claude/CLAUDE.md" "keep me below the mention"
  rm -rf "$home"
}

test_install_preserves_claude_md_mode() {
  local home mode
  home="$(mktemp -d)"
  mkdir -p "$home/.claude"
  printf '# graphify\nkeep me\n' > "$home/.claude/CLAUDE.md"
  chmod 600 "$home/.claude/CLAUDE.md"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  mode="$(stat -c '%a' "$home/.claude/CLAUDE.md")"
  assert_eq "$mode" "600" "CLAUDE.md mode after two installs"
  rm -rf "$home"
}

test_install_replaces_claude_md_atomically_via_rename() {
  local home
  home="$(mktemp -d)"
  mkdir -p "$home/.claude"
  printf '# graphify\nkeep me\n' > "$home/.claude/CLAUDE.md"
  # The directory stays writable, but CLAUDE.md itself has no write bit.
  # Replacing it via rename(2) (mv) needs only directory permission and
  # succeeds; truncating it open (cat > file) needs write permission on the
  # file itself and would fail. This distinguishes an atomic commit from the
  # non-atomic truncate-and-write regression.
  chmod 444 "$home/.claude/CLAUDE.md"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null 2>/dev/null
  assert_file_has "$home/.claude/CLAUDE.md" "keep me"
  assert_file_has "$home/.claude/CLAUDE.md" "<!-- promptify:begin -->"
  rm -rf "$home"
}

test_install_rejects_a_real_directory_at_the_skill_path() {
  local home rc
  home="$(mktemp -d)"
  mkdir -p "$home/.claude/skills/promptify"
  rc=0
  HOME="$home" bash "$ROOT/install.sh" >/dev/null 2>/dev/null || rc=$?
  [ "$rc" -ne 0 ] || fail "expected non-zero exit when a real directory occupies the skill path, got 0"
  [ ! -e "$home/.claude/skills/promptify/promptify" ] || fail "installer nested itself inside the pre-existing real directory"
  rm -rf "$home"
}

test_install_rejects_a_real_file_at_the_command_path() {
  local home rc out
  home="$(mktemp -d)"
  mkdir -p "$home/.claude/commands"
  printf 'not a symlink\n' > "$home/.claude/commands/p.md"
  rc=0
  out="$(HOME="$home" bash "$ROOT/install.sh" 2>&1 >/dev/null)" || rc=$?
  [ "$rc" -ne 0 ] || fail "expected non-zero exit when a real file occupies the /p command path, got 0"
  assert_contains "$out" "/p" "error message should mention the /p command"
  assert_eq "$(cat "$home/.claude/commands/p.md")" "not a symlink" "existing /p command content must not be overwritten"
  rm -rf "$home"
}

test_install_backs_up_existing_claude_md() {
  local home
  home="$(mktemp -d)"
  mkdir -p "$home/.claude"
  printf '# graphify\nkeep me\n' > "$home/.claude/CLAUDE.md"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  [ -f "$home/.claude/CLAUDE.md.bak" ] || fail "expected a CLAUDE.md.bak backup to be created"
  assert_file_has "$home/.claude/CLAUDE.md.bak" "keep me"
  rm -rf "$home"
}

test_install_edits_a_symlinked_claude_md_in_place() {
  local home n
  home="$(mktemp -d)"
  mkdir -p "$home/.claude" "$home/dotfiles"
  printf '# graphify\nkeep me\n' > "$home/dotfiles/CLAUDE.md"
  ln -s "$home/dotfiles/CLAUDE.md" "$home/.claude/CLAUDE.md"
  # Two installs: the symlink-destroying bug this guards against only fires
  # on the SECOND install, once a block already exists and the strip-and-
  # rewrite path actually runs.
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  [ -L "$home/.claude/CLAUDE.md" ] || fail "expected ~/.claude/CLAUDE.md to remain a symlink"
  assert_eq "$(readlink "$home/.claude/CLAUDE.md")" "$home/dotfiles/CLAUDE.md" "CLAUDE.md symlink target unchanged"
  assert_file_has "$home/dotfiles/CLAUDE.md" "keep me"
  n="$(grep -cF '<!-- promptify:begin -->' "$home/dotfiles/CLAUDE.md" || true)"
  assert_eq "$n" "1" "trigger block count in the real target after two installs"
  rm -rf "$home"
}
