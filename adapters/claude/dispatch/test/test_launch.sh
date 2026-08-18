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
  assert_eq "${CLAUDE_ARGV[6]}" "--settings"       "settings flag"
  assert_eq "${CLAUDE_ARGV[7]}" '{"editorMode":"vim"}' "Vim editor mode"
  assert_eq "${CLAUDE_ARGV[8]}" "--add-dir"        "add-dir must come last"
  assert_eq "${CLAUDE_ARGV[9]}" "/a"               "first dir"
  assert_eq "${CLAUDE_ARGV[10]}" "/b"              "second dir"
}

test_build_claude_argv_omits_add_dir_when_empty() {
  DISPATCH_CLAUDE_BIN=claude build_claude_argv "prompt" "id" auto
  assert_eq "${#CLAUDE_ARGV[@]}" "8" "no trailing --add-dir"
}

test_build_claude_argv_omits_permission_mode_when_empty() {
  DISPATCH_CLAUDE_BIN=claude build_claude_argv "prompt" "id" "" /a
  assert_eq "${CLAUDE_ARGV[4]}" "--settings" "Vim settings remain when permission mode is unset"
  assert_eq "${CLAUDE_ARGV[6]}" "--add-dir" "no --permission-mode when unset"
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
test_detect_mux_prefers_tmux_when_both_are_present() {
  local got
  got="$(DISPATCH_MUX="" TMUX=fake HERDR_ENV=1 detect_mux)"
  assert_eq "$got" "tmux" "tmux is the innermost multiplexer when both are set"
}

test_detect_mux_falls_back_to_herdr() {
  local got
  got="$(DISPATCH_MUX="" TMUX="" HERDR_ENV=1 detect_mux)"
  assert_eq "$got" "herdr" "herdr when HERDR_ENV is set and TMUX is not"
}

test_detect_mux_reports_none_when_bare() {
  local got
  got="$(DISPATCH_MUX="" TMUX="" HERDR_ENV="" detect_mux)"
  assert_eq "$got" "none" "no multiplexer at all"
}

test_detect_mux_honours_the_override() {
  local got
  got="$(DISPATCH_MUX=herdr TMUX=fake HERDR_ENV="" detect_mux)"
  assert_eq "$got" "herdr" "DISPATCH_MUX beats detection"
}

test_detect_mux_rejects_an_unknown_override() {
  DISPATCH_MUX=screen TMUX=fake detect_mux >/dev/null 2>&1 \
    && fail "an unsupported DISPATCH_MUX must not be accepted"
  return 0
}

# herdr's `pane run` evaluates a joined string in a shell rather than execing
# argv, so the prompt has to survive quoting as a single word. The stub evals
# the same way, which is what gives this test its teeth.
test_launch_window_herdr_keeps_the_prompt_as_one_argument() {
  local state="$SANDBOX/herdr-state" wt="$SANDBOX/wt"
  mkdir -p "$state" "$wt"

  DISPATCH_HERDR_STATE="$state" DISPATCH_HERDR_BIN="$ROOT/test/stub/herdr" \
    launch_window herdr "primary-slug" "$wt" \
      "$ROOT/test/stub/claude" \
      "/superpowers:brainstorming Read $SANDBOX/b.md - it is your briefing." \
      --session-id abc-123 --add-dir "/path with space" \
    || fail "herdr launch returned non-zero"

  [ -f "$wt/.dispatch-argv" ] || { fail "no argv recorded in the tab cwd"; return 0; }

  local -a argv=()
  mapfile -t argv <"$wt/.dispatch-argv"
  assert_eq "${argv[0]}" \
    "/superpowers:brainstorming Read $SANDBOX/b.md - it is your briefing." \
    "the whole prompt must arrive as argv[1]"
  assert_eq "${argv[1]}" "--session-id" "session flag follows the prompt"
  assert_eq "${argv[3]}" "--add-dir"    "add-dir still last"
  assert_eq "${argv[4]}" "/path with space" "a directory with spaces stays one argument"
}

test_launch_window_herdr_does_not_evaluate_substitutions_in_paths() {
  local state="$SANDBOX/herdr-state" wt="$SANDBOX/wt"
  mkdir -p "$state" "$wt"

  DISPATCH_HERDR_STATE="$state" DISPATCH_HERDR_BIN="$ROOT/test/stub/herdr" \
    launch_window herdr "primary-slug" "$wt" \
      "$ROOT/test/stub/claude" "prompt" --add-dir "/tmp/\$(touch $SANDBOX/PWNED)" \
    || fail "herdr launch returned non-zero"

  [ ! -e "$SANDBOX/PWNED" ] || fail "a command substitution in a path was executed"

  local -a argv=()
  mapfile -t argv <"$wt/.dispatch-argv"
  assert_eq "${argv[2]}" "/tmp/\$(touch $SANDBOX/PWNED)" "substitution passed through literally"
}

test_launch_window_herdr_reports_a_focus_hint() {
  local state="$SANDBOX/herdr-state" wt="$SANDBOX/wt"
  mkdir -p "$state" "$wt"

  LAUNCH_SWITCH_HINT=""
  DISPATCH_HERDR_STATE="$state" DISPATCH_HERDR_BIN="$ROOT/test/stub/herdr" \
    launch_window herdr "primary-slug" "$wt" "$ROOT/test/stub/claude" p >/dev/null

  assert_contains "$LAUNCH_SWITCH_HINT" "herdr tab focus"
  assert_eq "$(cat "$state/tab-label")" "primary-slug" "the tab is labelled like the window"
  assert_eq "$(cat "$state/tab-cwd")" "$wt" "the tab opens in the primary worktree"
}

test_launch_window_rejects_an_unknown_mux() {
  launch_window screen "n" "$SANDBOX" /bin/true >/dev/null 2>&1 \
    && fail "launch_window must refuse a multiplexer it does not implement"
  return 0
}

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
       launch_window tmux "hooked" "$SANDBOX" sh -c 'sleep 30'; then
    fail "launch_window returned non-zero despite the window being created"
  fi

  after="$(tmux -L "$sock" list-windows -a -F '#{window_id}' | wc -l)"
  assert_eq "$after" "$((before + 1))" "window created despite failing hook"
  assert_contains "$(tmux -L "$sock" list-windows -a -F '#{window_name}')" "hooked"

  tmux -L "$sock" kill-server 2>/dev/null || true
  rm -f "/tmp/tmux-$(id -u)/$sock"
}
