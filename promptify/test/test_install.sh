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
  assert_file_has "$home/.claude/CLAUDE.md" "promptify"
  assert_file_has "$home/.claude/CLAUDE.md" "<!-- promptify:begin -->"
  assert_file_has "$home/.claude/CLAUDE.md" "<!-- promptify:end -->"
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
  local home
  home="$(mktemp -d)"
  mkdir -p "$home/.claude"
  printf '# graphify\nkeep me\n' > "$home/.claude/CLAUDE.md"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  assert_file_has "$home/.claude/CLAUDE.md" "keep me"
  assert_file_has "$home/.claude/CLAUDE.md" "# graphify"
  rm -rf "$home"
}

test_install_handles_claude_md_without_trailing_newline() {
  local home n
  home="$(mktemp -d)"
  mkdir -p "$home/.claude"
  printf 'no trailing newline' > "$home/.claude/CLAUDE.md"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  assert_file_has "$home/.claude/CLAUDE.md" "no trailing newline"
  n="$(grep -cF '<!-- promptify:begin -->' "$home/.claude/CLAUDE.md")"
  assert_eq "$n" "1" "trigger block count"
  rm -rf "$home"
}
