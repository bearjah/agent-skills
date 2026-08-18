#!/usr/bin/env bash
# Hand an already-built command argv to the caller's terminal multiplexer.

# detect_mux
# Prints the multiplexer to launch into: tmux, herdr, or none.
# DISPATCH_MUX forces the choice; returns 2 if it names an unsupported one.
#
# tmux wins when both are present. herdr exports HERDR_ENV into every process
# it starts, so a tmux session running inside a herdr tab still carries it;
# the innermost multiplexer is the one whose window you are actually looking
# at, and that is the one the new window should appear in.
detect_mux() {
  case "${DISPATCH_MUX:-}" in
    tmux|herdr) printf '%s\n' "$DISPATCH_MUX"; return 0 ;;
    "")         ;;
    *)          return 2 ;;
  esac

  if [ -n "${TMUX:-}" ]; then
    printf 'tmux\n'
  elif [ "${HERDR_ENV:-}" = "1" ]; then
    printf 'herdr\n'
  else
    printf 'none\n'
  fi
}

# launch_window <mux> <window-name> <cwd> <argv...>
#
# Sets LAUNCH_SWITCH_HINT to the command that brings the new window to the
# front, which differs per multiplexer and goes into the dispatch report.
launch_window() {
  local mux="$1"
  shift
  case "$mux" in
    tmux)  launch_window_tmux "$@" ;;
    herdr) launch_window_herdr "$@" ;;
    *)     printf 'dispatch: unsupported multiplexer: %s\n' "$mux" >&2; return 1 ;;
  esac
}

# launch_window_tmux <window-name> <cwd> <argv...>
#
# tmux propagates the exit status of the user's after-new-window hooks, so a
# broken hook in ~/.tmux.conf is indistinguishable from a failed launch. Treat
# the window actually existing as the source of truth and downgrade a hook
# failure to a warning, so a dispatch that worked still reports its session id,
# transcript path, and cleanup command.
launch_window_tmux() {
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
    LAUNCH_SWITCH_HINT="tmux select-window -t $name"
    return 0
  fi

  [ -s "$err" ] && cat "$err" >&2
  rm -f "$err"
  return "$(( rc == 0 ? 1 : rc ))"
}

# herdr_field <json> <object> <key>
# herdr answers in JSON on stdout, so read it with a parser rather than a
# regex. Prints nothing when the field is absent.
herdr_field() {
  printf '%s' "$1" | python3 -c '
import json, sys
try:
    payload = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
obj = (payload.get("result") or {}).get(sys.argv[1]) or {}
value = obj.get(sys.argv[2])
if value is not None:
    print(value)
' "$2" "$3" 2>/dev/null
}

# launch_window_herdr <window-name> <cwd> <argv...>
#
# herdr has no single "open a tab running this command" call the way tmux does:
# `tab create` takes a cwd and a label but no command, so the pane comes up at a
# shell prompt and the command has to be sent in afterwards.
#
# `pane run` then joins its arguments with spaces and evaluates the result in
# that shell -- it does not exec argv. So every word must be quoted before it
# goes in, or the prompt would split into one argument per word and a $(...) in
# a brief path would execute. printf %q does exactly that quoting.
launch_window_herdr() {
  local name="$1" cwd="$2"
  shift 2
  local herdr="${DISPATCH_HERDR_BIN:-herdr}"
  local out pane_id tab_id cmd
  local -a workspace_arg=()

  # Put the tab in the CALLER's workspace, not in whichever one herdr happens
  # to be looking at. `tab create` has no workspace default of its own beyond
  # the focused one, so a dispatch fired from one workspace while the operator
  # had another on screen opens the tab over there -- six petal sessions landed
  # in an unrelated workspace that way (2026-08-16). The tmux backend has no
  # equivalent hole, which is why this went unnoticed.
  #
  # The answer is already in the environment: herdr exports HERDR_WORKSPACE_ID
  # into every process it starts. DISPATCH_HERDR_WORKSPACE overrides it, and
  # setting that to the empty string restores "let herdr decide" -- which is
  # also what happens when dispatch runs from outside a herdr tab and there is
  # no caller workspace to inherit.
  local workspace="${DISPATCH_HERDR_WORKSPACE-${HERDR_WORKSPACE_ID:-}}"
  [ -n "$workspace" ] && workspace_arg=(--workspace "$workspace")

  out="$("$herdr" tab create ${workspace_arg[@]+"${workspace_arg[@]}"} --cwd "$cwd" --label "$name" --no-focus 2>&1)" || {
    printf 'dispatch: herdr tab create failed: %s\n' "$out" >&2
    return 1
  }

  pane_id="$(herdr_field "$out" root_pane pane_id)"
  tab_id="$(herdr_field "$out" tab tab_id)"
  if [ -z "$pane_id" ]; then
    printf 'dispatch: no pane id in the herdr tab create reply: %s\n' "$out" >&2
    return 1
  fi

  cmd="$(printf '%q ' "$@")"
  out="$("$herdr" pane run "$pane_id" "$cmd" 2>&1)" || {
    printf 'dispatch: herdr pane run failed in %s: %s\n' "$pane_id" "$out" >&2
    return 1
  }

  LAUNCH_SWITCH_HINT="herdr tab focus ${tab_id:-$pane_id}"
  return 0
}
