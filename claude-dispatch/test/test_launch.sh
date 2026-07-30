#!/usr/bin/env bash
# shellcheck source=lib/launch.sh
source "$ROOT/lib/launch.sh"

test_build_claude_argv_puts_prompt_before_add_dir() {
  DISPATCH_CLAUDE_BIN=claude build_claude_argv "do the thing" "abc-123" auto /a /b
  assert_eq "${CLAUDE_ARGV[0]}" "claude"           "argv[0]"
  assert_eq "${CLAUDE_ARGV[1]}" "do the thing"     "prompt must be argv[1]"
  assert_eq "${CLAUDE_ARGV[2]}" "--session-id"     "session flag"
  assert_eq "${CLAUDE_ARGV[3]}" "abc-123"          "session id"
  assert_eq "${CLAUDE_ARGV[4]}" "--permission-mode" "permission flag"
  assert_eq "${CLAUDE_ARGV[5]}" "auto"             "permission mode"
  assert_eq "${CLAUDE_ARGV[6]}" "--add-dir"        "add-dir must come last"
  assert_eq "${CLAUDE_ARGV[7]}" "/a"               "first dir"
  assert_eq "${CLAUDE_ARGV[8]}" "/b"               "second dir"
}

test_build_claude_argv_omits_add_dir_when_empty() {
  DISPATCH_CLAUDE_BIN=claude build_claude_argv "prompt" "id" auto
  assert_eq "${#CLAUDE_ARGV[@]}" "6" "no trailing --add-dir"
}

test_build_claude_argv_omits_permission_mode_when_empty() {
  DISPATCH_CLAUDE_BIN=claude build_claude_argv "prompt" "id" "" /a
  assert_eq "${CLAUDE_ARGV[4]}" "--add-dir" "no --permission-mode when unset"
}

test_build_claude_argv_honours_binary_override() {
  DISPATCH_CLAUDE_BIN=/opt/stub/claude build_claude_argv "p" "i" auto
  assert_eq "${CLAUDE_ARGV[0]}" "/opt/stub/claude" "binary override"
}

# Regression: a user's after-new-window hook that fails makes `tmux new-window`
# return the hook's exit status, which is indistinguishable from a failed
# launch. Found by a live smoke test against a ~/.tmux.conf whose
# tmux-agent-sidebar binary was missing: the window and worktrees were created,
# but the dispatcher aborted before printing its report.
test_launch_window_survives_a_failing_tmux_hook() {
  command -v tmux >/dev/null 2>&1 || { printf '    SKIP: tmux absent\n'; return 0; }

  local sock="dispatch-unit-hook-$$"
  tmux -L "$sock" new-session -d 2>/dev/null || {
    printf '    SKIP: could not start private tmux server\n'; return 0
  }
  tmux -L "$sock" set-hook -g after-new-window \
    'run-shell "/nonexistent/definitely-not-a-real-binary"' 2>/dev/null

  local before after
  before="$(tmux -L "$sock" list-windows -a -F '#{window_id}' | wc -l)"

  if ! TMUX="$(tmux -L "$sock" display-message -p '#{socket_path},#{pid},0')" \
       launch_window "hooked" "$SANDBOX" sh -c 'sleep 30'; then
    fail "launch_window returned non-zero despite the window being created"
  fi

  after="$(tmux -L "$sock" list-windows -a -F '#{window_id}' | wc -l)"
  assert_eq "$after" "$((before + 1))" "window created despite failing hook"
  assert_contains "$(tmux -L "$sock" list-windows -a -F '#{window_name}')" "hooked"

  tmux -L "$sock" kill-server 2>/dev/null || true
  rm -f "/tmp/tmux-$(id -u)/$sock"
}
