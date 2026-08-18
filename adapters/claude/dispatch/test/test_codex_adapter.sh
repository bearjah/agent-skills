#!/usr/bin/env bash

CODEX_ROOT="$(cd "$ROOT/../../codex/dispatch" && pwd)"

test_codex_install_links_git_commit_skill() {
  local home skill_dir
  home="$SANDBOX/home"
  skill_dir="$(cd "$ROOT/../../../skills/git-commit" && pwd)"
  mkdir -p "$home"

  HOME="$home" AGENT_DOCS_ROOT="$SANDBOX/docs" \
    bash "$CODEX_ROOT/install.sh" >/dev/null

  [ -L "$home/.codex/skills/git-commit" ] || fail "Codex skill symlink missing"
  assert_eq "$(readlink "$home/.codex/skills/git-commit")" \
    "$skill_dir" "Codex git-commit link target"
}

test_codex_install_refuses_a_real_directory_at_git_commit_path() {
  local home rc
  home="$SANDBOX/home"
  mkdir -p "$home/.codex/skills/git-commit"
  rc=0

  HOME="$home" AGENT_DOCS_ROOT="$SANDBOX/docs" \
    bash "$CODEX_ROOT/install.sh" >/dev/null 2>&1 || rc=$?

  [ "$rc" -ne 0 ] || fail "expected Codex install to reject a real skill dir"
  [ ! -e "$home/.codex/skills/promptify" ] \
    || fail "a rejected Codex install still linked an earlier skill"
  [ ! -e "$home/.codex/scripts/dispatch-task.sh" ] \
    || fail "a rejected Codex install still linked the dispatch script"
}

test_codex_dispatch_uses_configured_docs_root() {
  mkdir -p "$SANDBOX/herdr"
  mkrepo "$SANDBOX/repo" main
  mkremote "$SANDBOX/repo"
  printf 'review brief\n' > "$SANDBOX/review.md"

  TMUX='' HERDR_ENV=1 DISPATCH_MUX=herdr \
  DISPATCH_HERDR_BIN="$ROOT/test/stub/herdr" \
  DISPATCH_HERDR_STATE="$SANDBOX/herdr" \
  DISPATCH_CODEX_BIN="$ROOT/test/stub/claude" \
  DISPATCH_WORKTREE_ROOT="$SANDBOX/worktrees" \
  AGENT_DOCS_ROOT="$SANDBOX/docs" \
    "$CODEX_ROOT/bin/dispatch-task.sh" \
      --slug codex-docs --brief "$SANDBOX/review.md" \
      --target "$SANDBOX/repo" >/dev/null \
    || { fail "Codex dispatch exited non-zero"; return; }

  local wt="$SANDBOX/worktrees/repo/codex-docs" argv=()
  mapfile -t argv < "$wt/.dispatch-argv"
  [ -f "$SANDBOX/docs/dispatch/review.md" ] || fail "Codex did not stage the brief"
  assert_contains "${argv[*]}" "$SANDBOX/docs"
  assert_contains "${argv[*]}" "$SANDBOX/docs/dispatch/review.md"
  assert_contains "${argv[*]}" "never in a target repository's docs directory"
  assert_contains "${argv[*]}" "tui.vim_mode_default=true"
}
