#!/usr/bin/env bash
# Building the CLI argv and handing it to tmux.

# build_claude_argv <prompt> <session-id> <permission-mode> [add-dir...]
# Sets the global array CLAUDE_ARGV.
#
# Order matters: --add-dir is variadic, so anything after it is consumed as a
# directory. The prompt MUST precede it, and every other flag must sit between
# the two.
#
# An empty permission-mode omits the flag entirely, deferring to whatever the
# CLI and the user's settings decide.
build_claude_argv() {
  local prompt="$1" session_id="$2" permission_mode="$3"
  shift 3
  CLAUDE_ARGV=("${DISPATCH_CLAUDE_BIN:-claude}" "$prompt" --session-id "$session_id")
  if [ -n "$permission_mode" ]; then
    CLAUDE_ARGV+=(--permission-mode "$permission_mode")
  fi
  if [ "$#" -gt 0 ]; then
    CLAUDE_ARGV+=(--add-dir "$@")
  fi
}

# launch_window <window-name> <cwd> <argv...>
#
# tmux propagates the exit status of the user's after-new-window hooks, so a
# broken hook in ~/.tmux.conf is indistinguishable from a failed launch. Treat
# the window actually existing as the source of truth and downgrade a hook
# failure to a warning, so a dispatch that worked still reports its session id,
# transcript path, and cleanup command.
launch_window() {
  local name="$1" cwd="$2"
  shift 2
  local wid err rc=0
  err="$(mktemp)"
  wid="$(tmux new-window -d -P -F '#{window_id}' -n "$name" -c "$cwd" -- "$@" 2>"$err")" || rc=$?

  if [ -n "$wid" ] && tmux list-windows -a -F '#{window_id}' 2>/dev/null | grep -qxF "$wid"; then
    if [ "$rc" -ne 0 ] && [ -s "$err" ]; then
      printf 'dispatch: warning: a tmux hook failed (exit %s); the window was created anyway:\n' "$rc" >&2
      sed 's/^/  /' "$err" >&2
    fi
    rm -f "$err"
    return 0
  fi

  [ -s "$err" ] && cat "$err" >&2
  rm -f "$err"
  return "$(( rc == 0 ? 1 : rc ))"
}
