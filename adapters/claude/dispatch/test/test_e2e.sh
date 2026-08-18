#!/usr/bin/env bash
# End-to-end dispatch against a stub binary that records its argv.
#
# The window is created on a PRIVATE tmux server, never the caller's live one:
# a unit suite must not add windows to the session the developer is sitting in.

# _e2e_body <tmux-env> - the assertions, with the server already running
_e2e_body() {
  local tmux_env="$1"

  mkdir -p "$SANDBOX/code/org"
  mkrepo "$SANDBOX/code/org/primary" main;  mkremote "$SANDBOX/code/org/primary"
  mkrepo "$SANDBOX/code/org/second"  main;  mkremote "$SANDBOX/code/org/second"
  mkrepo "$SANDBOX/code/org/refonly" main;  mkremote "$SANDBOX/code/org/refonly"
  printf 'the briefing\n' > "$SANDBOX/brief.md"

  TMUX="$tmux_env" \
  DISPATCH_CLAUDE_BIN="$ROOT/test/stub/claude" \
  DISPATCH_SEARCH_GLOB="$SANDBOX/code/*" \
  DISPATCH_WORKTREE_ROOT="$SANDBOX/worktrees" \
  AGENT_DOCS_ROOT="$SANDBOX/docs" \
    "$ROOT/bin/dispatch-task.sh" \
      --slug e2e --brief "$SANDBOX/brief.md" \
      --target primary --target second --ref refonly >/dev/null \
    || { fail "dispatch exited non-zero"; return; }

  local wt="$SANDBOX/worktrees/primary/e2e" argv=() i
  for ((i = 0; i < 100; i++)); do
    [ -s "$wt/.dispatch-argv" ] && break
    sleep 0.1
  done
  [ -s "$wt/.dispatch-argv" ] || { fail "stub never ran in $wt"; return; }

  mapfile -t argv < "$wt/.dispatch-argv"
  assert_contains "${argv[0]}" "superpowers:brainstorming"
  assert_contains "${argv[0]}" "$SANDBOX/docs/dispatch/brief.md"
  assert_eq "${argv[1]}" "--session-id" "session flag position"
  assert_eq "${argv[3]}" "--permission-mode" "permission mode follows the session id"
  assert_eq "${argv[4]}" "auto" "dispatched sessions default to auto"

  # Relational, not positional: flags may be added between the session id and
  # --add-dir, but --add-dir is variadic so it must always come last.
  local add_idx=-1 i
  for i in "${!argv[@]}"; do
    [ "${argv[$i]}" = "--add-dir" ] && { add_idx="$i"; break; }
  done
  [ "$add_idx" -gt 2 ] || fail "--add-dir must follow the prompt and session id"

  local rest="${argv[*]:$((add_idx + 1))}"
  assert_contains "$rest" "$SANDBOX/worktrees/second/e2e"
  assert_contains "$rest" "$SANDBOX/code/org/refonly"
  assert_contains "$rest" "$SANDBOX/docs"
  [ -f "$SANDBOX/docs/dispatch/brief.md" ] || fail "brief was not stored in docs root"
  [ ! -d "$SANDBOX/worktrees/refonly/e2e" ] || fail "ref repo got a worktree"
}

test_e2e_dispatch_launches_with_correct_argv_and_cwd() {
  if ! command -v tmux >/dev/null 2>&1; then
    printf '    SKIP: tmux is not installed\n'
    return 0
  fi

  local sock="dispatch-unit-$$" tmux_env socket_path
  if ! tmux -L "$sock" new-session -d -s e2e -x 80 -y 24 >/dev/null 2>&1; then
    printf '    SKIP: could not start a private tmux server on %s\n' "$sock"
    return 0
  fi
  tmux -L "$sock" set-option -g remain-on-exit on >/dev/null 2>&1 || true
  tmux_env="$(tmux -L "$sock" display-message -p '#{socket_path},#{pid},0')"

  _e2e_body "$tmux_env"

  # kill-server leaves the socket inode behind, so unlink it too.
  tmux -L "$sock" kill-server >/dev/null 2>&1 || true
  socket_path="${tmux_env%%,*}"
  [ -n "$socket_path" ] && [ -S "$socket_path" ] && rm -f "$socket_path"
  return 0
}
