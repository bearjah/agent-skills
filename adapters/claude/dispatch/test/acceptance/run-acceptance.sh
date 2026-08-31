#!/usr/bin/env bash
#
# Acceptance gate for the task-dispatch tool.
#
#   ./test/acceptance/run-acceptance.sh            # every case
#   ./test/acceptance/run-acceptance.sh ac_05_...  # one case
#
# One function per acceptance criterion in
# ~/docs/validation/2026-07-27-task-dispatch-tool-validation.md.
#
# SELF-CONTAINED BY DESIGN. This file carries its own runner, assertions and
# fixtures. It sources nothing from the implementation (no test/helpers.sh, no
# lib/*.sh) and drives bin/dispatch-task.sh only as a subprocess, so it is
# runnable — and legitimately failing — before any implementation exists.
#
# Isolation:
#   * a private tmux server on socket dispatch-acc-$$; the caller's live tmux
#     session is never touched
#   * one mktemp -d per case, removed in teardown
#   * HOME is redirected to a temp dir for the installer cases
#   * no network: fixture origins are local bare repos
#
set -uo pipefail

ACC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$ACC_DIR/../.." && pwd)"
ENTRYPOINT="$ROOT/bin/dispatch-task.sh"
INSTALLER="$ROOT/install.sh"
STUB="$ACC_DIR/stub/claude"
HERDR_STUB="$ROOT/test/stub/herdr"
ACC_HERDR_ENV=""
ACC_HERDR_WORKSPACE=""

SOCK="dispatch-acc-$$"
TMUX_ENV=""
RUNDIR=""

TESTS_RUN=0
TESTS_FAILED=0
CASE_FAILED=0
TC=""

# Captured results of the last subprocess run.
DRC=0
DOUT=""
DERR=""
RC=0
OUT=""
ERR=""
RUN_ENV=()
ARGV=()

CASES=(
  ac_01_requires_a_multiplexer
  ac_02_requires_brief
  ac_03_repo_resolution
  ac_04_rejects_existing_worktree_or_branch
  ac_05_primary_is_cwd
  ac_06_targets_get_local_worktrees
  ac_07_refs_get_no_worktree
  ac_08_add_dir_contents
  ac_09_argv_order
  ac_10_prompt_skill_and_brief
  ac_11_single_window_named
  ac_12_report_fields
  ac_13_base_ref_resolution
  ac_14_cleanup_removes
  ac_15_cleanup_refuses_dirty
  ac_16_cleanup_refuses_unmerged
  ac_17_install_symlinks_work
  ac_18_install_preserves_unrelated_tooling
  ac_19_herdr_backend_launches
  ac_20_herdr_workspace_fallback_and_override
)

# --------------------------------------------------------------------------
# Assertions
# --------------------------------------------------------------------------

# Flatten a possibly-multiline value so a failure message stays one line.
flat() {
  printf '%s' "$1" | tr '\n' '|' | cut -c1-500
}

fail() {
  printf '    FAIL: %s\n' "$1"
  CASE_FAILED=1
}

assert_eq() {
  local actual="$1" expected="$2" label="${3:-}"
  [ "$actual" = "$expected" ] ||
    fail "${label:+$label: }expected '$(flat "$expected")', got '$(flat "$actual")'"
}

assert_ne() {
  local actual="$1" unexpected="$2" label="${3:-}"
  [ "$actual" != "$unexpected" ] ||
    fail "${label:+$label: }expected a value other than '$(flat "$unexpected")'"
}

assert_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  case "$haystack" in
    *"$needle"*) ;;
    *) fail "${label:+$label: }expected to contain '$(flat "$needle")', got '$(flat "$haystack")'" ;;
  esac
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  case "$haystack" in
    *"$needle"*) fail "${label:+$label: }expected NOT to contain '$(flat "$needle")', got '$(flat "$haystack")'" ;;
    *) ;;
  esac
}

assert_starts_with() {
  local haystack="$1" prefix="$2" label="${3:-}"
  case "$haystack" in
    "$prefix"*) ;;
    *) fail "${label:+$label: }expected to start with '$(flat "$prefix")', got '$(flat "$haystack")'" ;;
  esac
}

assert_match() {
  local subject="$1" regex="$2" label="${3:-}"
  # Deliberately unquoted: $regex is an ERE, not a literal.
  if ! [[ "$subject" =~ $regex ]]; then
    fail "${label:+$label: }expected to match /$regex/, got '$(flat "$subject")'"
  fi
}

assert_zero() {
  local rc="$1" label="${2:-}"
  [ "$rc" -eq 0 ] || fail "${label:+$label: }expected exit 0, got $rc"
}

assert_nonzero() {
  local rc="$1" label="${2:-}"
  [ "$rc" -ne 0 ] || fail "${label:+$label: }expected a non-zero exit, got $rc"
}

assert_dir() {
  local path="$1" label="${2:-}"
  [ -d "$path" ] || fail "${label:+$label: }expected directory to exist: $path"
}

assert_absent() {
  local path="$1" label="${2:-}"
  [ ! -e "$path" ] || fail "${label:+$label: }expected path to be absent: $path"
}

# assert_no_worktrees <root> [label] - no repo/slug worktree was created
assert_no_worktrees() {
  local dir="$1" label="${2:-}" found
  found="$(find "$dir" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | tr '\n' ' ')"
  [ -z "${found// /}" ] ||
    fail "${label:+$label: }expected no worktrees under $dir, found: $found"
}

# --------------------------------------------------------------------------
# Bounded polling, with no sleep-based synchronisation
# --------------------------------------------------------------------------

# A fifo held open read-write never reaches EOF, so a timed read on it is a
# precise delay built from a bash builtin. 200 ticks x 50ms = a 10s ceiling.
tick() {
  read -r -t 0.05 -u 9 _ 2>/dev/null || true
}

poll_for_file() {
  local path="$1" i
  for ((i = 0; i < 200; i++)); do
    [ -s "$path" ] && return 0
    tick
  done
  return 1
}

# poll_for_dispatch_argv <worktree>
# A dispatch that exited non-zero launched nothing, so waiting out the ceiling
# would only slow the suite down. Anything else gets the full bounded wait.
poll_for_dispatch_argv() {
  [ "$DRC" -eq 0 ] || return 1
  poll_for_file "$1/.dispatch-argv"
}

poll_for_window() {
  local name="$1" i
  for ((i = 0; i < 200; i++)); do
    if tmux -L "$SOCK" list-windows -a -F '#{window_name}' 2>/dev/null |
      grep -Fxq -- "$name"; then
      return 0
    fi
    tick
  done
  return 1
}

# --------------------------------------------------------------------------
# tmux: a private server, never the caller's
# --------------------------------------------------------------------------

tmux_start() {
  tmux -L "$SOCK" new-session -d -s acceptance -x 80 -y 24 >/dev/null 2>&1 || return 1
  # Dead windows must linger, or a window count taken after the stub exits
  # would miss the window the dispatch created.
  tmux -L "$SOCK" set-option -g remain-on-exit on >/dev/null 2>&1 || return 1
  # Keep the window name the dispatcher chose exactly as it chose it.
  tmux -L "$SOCK" set-option -g automatic-rename off >/dev/null 2>&1 || true
  TMUX_ENV="$(tmux -L "$SOCK" display-message -p '#{socket_path},#{pid},0')"
  [ -n "$TMUX_ENV" ]
}

tmux_window_count() {
  tmux -L "$SOCK" list-windows -a 2>/dev/null | grep -c . || true
}

teardown_run() {
  tmux -L "$SOCK" kill-server >/dev/null 2>&1 || true
  # kill-server stops the server but leaves the socket inode behind, so unlink
  # it as well and leave /tmp/tmux-*/ exactly as the run found it.
  local socket_path="${TMUX_ENV%%,*}"
  [ -n "$socket_path" ] && [ -S "$socket_path" ] && rm -f "$socket_path"
  exec 9>&- 2>/dev/null || true
  [ -n "$RUNDIR" ] && rm -rf "$RUNDIR"
  return 0
}

# --------------------------------------------------------------------------
# Fixtures: real git repos with local bare origins
# --------------------------------------------------------------------------

# mk_repo <path> [branch] - a git repo with one commit
mk_repo() {
  local path="$1" branch="${2:-main}"
  mkdir -p "$path"
  git -C "$path" init -q -b "$branch" >/dev/null 2>&1
  git -C "$path" config user.email acceptance@example.invalid
  git -C "$path" config user.name "Acceptance Suite"
  git -C "$path" config commit.gpgsign false
  printf 'seed\n' >"$path/README.md"
  # The stub's recording is an artifact of the harness, not of the task, so
  # keep it out of `git status` the way the real project's .gitignore does.
  printf '.dispatch-argv\n.dispatch-argv.tmp\n' >"$path/.gitignore"
  git -C "$path" add -A
  git -C "$path" commit -qm "init"
}

# mk_origin <path> - give an existing repo a bare origin with origin/HEAD set
mk_origin() {
  local path="$1" branch
  branch="$(git -C "$path" branch --show-current)"
  git init -q --bare -b "$branch" "$path.git"
  git -C "$path" remote add origin "$path.git"
  git -C "$path" push -q -u origin HEAD
  git -C "$path" remote set-head origin -a >/dev/null 2>&1
}

# mk_std_repo <path> [branch] - repo plus origin
mk_std_repo() {
  mk_repo "$1" "${2:-main}"
  mk_origin "$1"
}

# add_local_commit <repo> <text> - a commit that is NOT pushed to origin
add_local_commit() {
  printf '%s\n' "$2" >>"$1/README.md"
  git -C "$1" commit -qam "$2"
}

# wt_path <repo> <slug> - the PWD-local Claude worktree path the tool must use
wt_path() {
  printf '%s/.claude/worktrees/%s/%s\n' "$TC" "$(basename "$1")" "$2"
}

# --------------------------------------------------------------------------
# Subprocess drivers
# --------------------------------------------------------------------------

# _dispatch <tmux-value> <args...>
# Never execs a missing or non-executable entrypoint: a synthetic result keeps
# the failure an assertion mismatch rather than a harness error.
_dispatch() {
  local tmux_value="$1"
  shift
  DRC=0
  DOUT=""
  DERR=""
  if [ ! -f "$ENTRYPOINT" ]; then
    DERR="acceptance: entrypoint is not present at $ENTRYPOINT"
    DRC=127
    return 0
  fi
  if [ ! -x "$ENTRYPOINT" ]; then
    DERR="acceptance: entrypoint at $ENTRYPOINT is not executable"
    DRC=126
    return 0
  fi
  # HERDR_ENV, HERDR_WORKSPACE_ID and DISPATCH_MUX are pinned rather than
  # inherited. herdr exports the first two into everything it starts, so a suite
  # run from inside a herdr tab would otherwise pick the herdr backend and open
  # real tabs in the operator's live session -- and, since the workspace is read
  # from the environment too, would assert against whichever workspace the
  # operator happened to be in rather than against a fixture.
  (
    cd "$TC" || exit 1
    env \
      TMUX="$tmux_value" \
      HERDR_ENV="$ACC_HERDR_ENV" \
      HERDR_WORKSPACE_ID="$ACC_HERDR_WORKSPACE" \
      DISPATCH_MUX="" \
      DISPATCH_WORKTREE_ROOT="" \
      DISPATCH_HERDR_BIN="$HERDR_STUB" \
      DISPATCH_HERDR_STATE="$TC/herdr-state" \
      DISPATCH_CLAUDE_BIN="$STUB" \
      DISPATCH_SEARCH_GLOB="$TC/code/*" \
      AGENT_DOCS_ROOT="$TC/docs" \
      "$ENTRYPOINT" "$@"
  ) >"$TC/.acc-stdout" 2>"$TC/.acc-stderr"
  DRC=$?
  DOUT="$(cat "$TC/.acc-stdout")"
  DERR="$(cat "$TC/.acc-stderr")"
  return 0
}

run_dispatch() {
  ACC_HERDR_ENV="" ACC_HERDR_WORKSPACE="" _dispatch "$TMUX_ENV" "$@"
}

run_dispatch_without_tmux() {
  ACC_HERDR_ENV="" ACC_HERDR_WORKSPACE="" _dispatch "" "$@"
}

# No TMUX, HERDR_ENV=1: the herdr backend, driven against the stub. The caller
# is placed in workspace w9 so the tab-placement assertion has a fixture to
# check rather than the operator's live workspace.
run_dispatch_herdr() {
  mkdir -p "$TC/herdr-state"
  ACC_HERDR_ENV=1 ACC_HERDR_WORKSPACE="${ACC_HERDR_WORKSPACE:-w9}" _dispatch "" "$@"
}

# The herdr backend with no caller workspace to inherit -- dispatch run from a
# shell herdr did not start.
run_dispatch_herdr_no_workspace() {
  mkdir -p "$TC/herdr-state"
  ACC_HERDR_ENV=1 ACC_HERDR_WORKSPACE="" _dispatch "" "$@"
}

# run_capture <exe> [args...] - environment supplied via the RUN_ENV array
run_capture() {
  local exe="$1"
  shift
  RC=0
  OUT=""
  ERR=""
  if [ ! -e "$exe" ]; then
    ERR="acceptance: $exe is not present"
    RC=127
    return 0
  fi
  if [ ! -x "$exe" ]; then
    ERR="acceptance: $exe is not executable"
    RC=126
    return 0
  fi
  env ${RUN_ENV[@]+"${RUN_ENV[@]}"} "$exe" "$@" >"$TC/.acc-stdout" 2>"$TC/.acc-stderr"
  RC=$?
  OUT="$(cat "$TC/.acc-stdout")"
  ERR="$(cat "$TC/.acc-stderr")"
  return 0
}

# --------------------------------------------------------------------------
# Recorded argv helpers
# --------------------------------------------------------------------------

read_argv() {
  ARGV=()
  mapfile -t ARGV <"$1"
}

argv_at() {
  printf '%s\n' "${ARGV[$1]-}"
}

argv_index_of() {
  local needle="$1" i
  for i in "${!ARGV[@]}"; do
    if [ "${ARGV[$i]}" = "$needle" ]; then
      printf '%s\n' "$i"
      return 0
    fi
  done
  printf '%s\n' "-1"
}

argv_tail_from() {
  local start="$1"
  printf '%s\n' "${ARGV[@]:start}"
}

# load_dispatch_argv <worktree> <label> - poll, then read. Returns 1 on timeout.
load_dispatch_argv() {
  local wt="$1" label="${2:-}"
  if ! poll_for_dispatch_argv "$wt"; then
    fail "${label:+$label: }no .dispatch-argv was recorded in $wt (dispatch exit $DRC)"
    ARGV=()
    return 1
  fi
  read_argv "$wt/.dispatch-argv"
  return 0
}

# --------------------------------------------------------------------------
# AC-1: $TMUX unset is a hard fail
# --------------------------------------------------------------------------
ac_01_requires_a_multiplexer() {
  mkdir -p "$TC/code/org"
  mk_std_repo "$TC/code/org/primary"
  printf '# brief\n' >"$TC/brief.md"

  run_dispatch_without_tmux --slug ac1 --brief "$TC/brief.md" --target primary

  assert_nonzero "$DRC" "exit status with neither TMUX nor HERDR_ENV"
  assert_contains "$DERR" "no supported terminal multiplexer" "stderr"
  assert_contains "$DERR" "herdr" "the error must name both supported multiplexers"
  assert_absent "$(wt_path "$TC/code/org/primary" ac1)" "worktree after a rejected dispatch"
  assert_no_worktrees "$TC/.claude/worktrees" "preflight must leave nothing behind"
}

# --------------------------------------------------------------------------
# AC-2: a missing brief is a hard fail
# --------------------------------------------------------------------------
ac_02_requires_brief() {
  mkdir -p "$TC/code/org"
  mk_std_repo "$TC/code/org/primary"

  run_dispatch --slug ac2 --brief "$TC/definitely-missing.md" --target primary

  assert_nonzero "$DRC" "exit status with a missing brief"
  assert_contains "$DERR" "brief not found" "stderr"
  assert_absent "$(wt_path "$TC/code/org/primary" ac2)" "worktree after a rejected dispatch"
  assert_no_worktrees "$TC/.claude/worktrees" "preflight must leave nothing behind"
}

# --------------------------------------------------------------------------
# AC-3: unknown or ambiguous repo names are hard errors listing candidates
# --------------------------------------------------------------------------
ac_03_repo_resolution() {
  mkdir -p "$TC/code/a" "$TC/code/b"
  mk_std_repo "$TC/code/a/images"
  mk_std_repo "$TC/code/b/images"
  printf '# brief\n' >"$TC/brief.md"

  run_dispatch --slug ac3u --brief "$TC/brief.md" --target nosuchrepo
  assert_nonzero "$DRC" "unknown repo exit status"
  assert_contains "$DERR" "no repo named" "unknown repo stderr"
  assert_no_worktrees "$TC/.claude/worktrees" "unknown repo must create nothing"

  run_dispatch --slug ac3a --brief "$TC/brief.md" --target images
  assert_nonzero "$DRC" "ambiguous repo exit status"
  assert_contains "$DERR" "ambiguous" "ambiguous repo stderr"
  assert_contains "$DERR" "$TC/code/a/images" "first candidate is listed"
  assert_contains "$DERR" "$TC/code/b/images" "second candidate is listed"
  assert_no_worktrees "$TC/.claude/worktrees" "ambiguous repo must create nothing"
}

# --------------------------------------------------------------------------
# AC-4: an existing worktree path or dispatch branch is a hard fail
# --------------------------------------------------------------------------
ac_04_rejects_existing_worktree_or_branch() {
  mkdir -p "$TC/code/org"
  mk_std_repo "$TC/code/org/primary"
  mk_std_repo "$TC/code/org/second"
  printf '# brief\n' >"$TC/brief.md"

  # (a) the worktree directory already exists and must survive untouched
  local squatter
  squatter="$(wt_path "$TC/code/org/primary" ac4)"
  mkdir -p "$squatter"
  printf 'do not touch me\n' >"$squatter/keep.txt"
  local before_hash after_hash entries
  before_hash="$(sha256sum <"$squatter/keep.txt")"

  run_dispatch --slug ac4 --brief "$TC/brief.md" --target primary
  assert_nonzero "$DRC" "existing worktree path exit status"
  assert_contains "$DERR" "already exists" "existing worktree path stderr"
  assert_dir "$squatter" "pre-existing directory must survive"
  after_hash="$(sha256sum <"$squatter/keep.txt" 2>/dev/null || printf 'MISSING')"
  assert_eq "$after_hash" "$before_hash" "pre-existing file must be unmodified"
  entries="$(find "$squatter" -mindepth 1 | grep -c . || true)"
  assert_eq "$entries" "1" "pre-existing directory must gain no entries"

  # (b) the dispatch/<slug> branch already exists
  git -C "$TC/code/org/second" branch dispatch/ac4b >/dev/null 2>&1
  run_dispatch --slug ac4b --brief "$TC/brief.md" --target second
  assert_nonzero "$DRC" "existing branch exit status"
  assert_contains "$DERR" "already exists" "existing branch stderr"
  assert_absent "$(wt_path "$TC/code/org/second" ac4b)" "no worktree for a rejected dispatch"
}

# --------------------------------------------------------------------------
# AC-5: cwd is the primary repo's worktree
# --------------------------------------------------------------------------
ac_05_primary_is_cwd() {
  mkdir -p "$TC/code/org"
  mk_std_repo "$TC/code/org/primary"
  mk_std_repo "$TC/code/org/second"
  printf '# brief\n' >"$TC/brief.md"

  run_dispatch --slug ac5 --brief "$TC/brief.md" --target primary --target second
  assert_zero "$DRC" "dispatch exit status (stderr: $(flat "$DERR"))"

  local expected
  expected="$(wt_path "$TC/code/org/primary" ac5)"
  if ! poll_for_dispatch_argv "$expected"; then
    fail "the stub never recorded argv in the primary worktree $expected (dispatch exit $DRC)"
  fi

  local found=()
  mapfile -t found < <(find "$TC" -name .dispatch-argv -type f 2>/dev/null | sort)
  assert_eq "${#found[@]}" "1" "exactly one .dispatch-argv in the sandbox"
  assert_eq "${found[0]-<none>}" "$expected/.dispatch-argv" ".dispatch-argv location"
}

# --------------------------------------------------------------------------
# AC-6: every target gets a PWD-local worktree on dispatch/<slug>
# --------------------------------------------------------------------------
ac_06_targets_get_local_worktrees() {
  mkdir -p "$TC/code/org"
  mk_std_repo "$TC/code/org/primary"
  mk_std_repo "$TC/code/org/second"
  printf '# brief\n' >"$TC/brief.md"

  run_dispatch --slug ac6 --brief "$TC/brief.md" --target primary --target second
  assert_zero "$DRC" "dispatch exit status (stderr: $(flat "$DERR"))"

  local repo wt branch
  for repo in primary second; do
    wt="$(wt_path "$TC/code/org/$repo" ac6)"
    assert_dir "$wt" "PWD-local worktree for $repo"
    branch="$(git -C "$wt" branch --show-current 2>/dev/null || printf '<no worktree>')"
    assert_eq "$branch" "dispatch/ac6" "branch checked out in $repo's worktree"
  done
}

# --------------------------------------------------------------------------
# AC-7: reference repos are read-only and get no worktree
# --------------------------------------------------------------------------
ac_07_refs_get_no_worktree() {
  mkdir -p "$TC/code/org"
  mk_std_repo "$TC/code/org/primary"
  mk_std_repo "$TC/code/org/refonly"
  printf '# brief\n' >"$TC/brief.md"

  local ref="$TC/code/org/refonly"
  local before_branch before_head before_status
  before_branch="$(git -C "$ref" branch --show-current)"
  before_head="$(git -C "$ref" rev-parse HEAD)"
  before_status="$(git -C "$ref" status --porcelain)"

  run_dispatch --slug ac7 --brief "$TC/brief.md" --target primary --ref refonly
  assert_zero "$DRC" "dispatch exit status (stderr: $(flat "$DERR"))"
  assert_dir "$(wt_path "$TC/code/org/primary" ac7)" "the dispatch really ran"

  assert_absent "$(wt_path "$TC/code/org/refonly" ac7)" "a reference repo must get no worktree"
  assert_eq "$(git -C "$ref" branch --show-current)" "$before_branch" "ref repo branch"
  assert_eq "$(git -C "$ref" rev-parse HEAD)" "$before_head" "ref repo HEAD"
  assert_eq "$(git -C "$ref" status --porcelain)" "$before_status" "ref repo working tree"
}

# --------------------------------------------------------------------------
# AC-8: secondary worktrees are reached via --add-dir
# --------------------------------------------------------------------------
ac_08_add_dir_contents() {
  mkdir -p "$TC/code/org"
  mk_std_repo "$TC/code/org/primary"
  mk_std_repo "$TC/code/org/second"
  mk_std_repo "$TC/code/org/refonly"
  printf '# brief\n' >"$TC/brief.md"

  run_dispatch --slug ac8 --brief "$TC/brief.md" \
    --target primary --target second --ref refonly
  assert_zero "$DRC" "dispatch exit status (stderr: $(flat "$DERR"))"

  load_dispatch_argv "$(wt_path "$TC/code/org/primary" ac8)" "recorded argv" || return 0

  local add_idx second_idx ref_idx
  add_idx="$(argv_index_of "--add-dir")"
  second_idx="$(argv_index_of "$(wt_path "$TC/code/org/second" ac8)")"
  ref_idx="$(argv_index_of "$TC/code/org/refonly")"

  assert_ne "$add_idx" "-1" "--add-dir is present in argv"
  assert_ne "$second_idx" "-1" \
    "the secondary target's worktree is in argv (argv: $(flat "$(argv_tail_from 0)"))"
  assert_ne "$ref_idx" "-1" \
    "the reference repo's original checkout is in argv (argv: $(flat "$(argv_tail_from 0)"))"

  if [ "$add_idx" -ge 0 ] && [ "$second_idx" -ge 0 ]; then
    [ "$second_idx" -gt "$add_idx" ] ||
      fail "secondary worktree at index $second_idx must follow --add-dir at $add_idx"
  fi
  if [ "$add_idx" -ge 0 ] && [ "$ref_idx" -ge 0 ]; then
    [ "$ref_idx" -gt "$add_idx" ] ||
      fail "reference checkout at index $ref_idx must follow --add-dir at $add_idx"
  fi
}

# --------------------------------------------------------------------------
# AC-9: argv order - prompt first, variadic --add-dir last
# --------------------------------------------------------------------------
ac_09_argv_order() {
  mkdir -p "$TC/code/org"
  mk_std_repo "$TC/code/org/primary"
  mk_std_repo "$TC/code/org/second"
  printf '# brief\n' >"$TC/brief.md"

  run_dispatch --slug ac9 --brief "$TC/brief.md" --target primary --target second
  assert_zero "$DRC" "dispatch exit status (stderr: $(flat "$DERR"))"

  load_dispatch_argv "$(wt_path "$TC/code/org/primary" ac9)" "recorded argv" || return 0

  local prompt sid_idx add_idx uuid
  prompt="$(argv_at 0)"
  assert_not_contains "${prompt:0:2}" "--" "argv[0] must be the prompt, not a flag"
  assert_contains "$prompt" "$TC/docs/dispatch/brief.md" \
    "argv[0] is the prompt naming the staged brief"

  sid_idx="$(argv_index_of "--session-id")"
  assert_eq "$sid_idx" "1" "--session-id must immediately follow the prompt"
  if [ "$sid_idx" -lt 0 ]; then
    fail "--session-id is absent from argv: $(flat "$(argv_tail_from 0)")"
    return 0
  fi

  uuid="$(argv_at $((sid_idx + 1)))"
  assert_eq "${#uuid}" "36" "the session id is 36 characters"
  assert_match "$uuid" '^[0-9a-f-]{36}$' "the session id looks like a uuid"

  add_idx="$(argv_index_of "--add-dir")"
  assert_ne "$add_idx" "-1" "--add-dir is present in argv"
  if [ "$add_idx" -ge 0 ]; then
    [ "$add_idx" -gt $((sid_idx + 1)) ] ||
      fail "--add-dir at index $add_idx must follow the prompt and the session id"
  fi
}

# --------------------------------------------------------------------------
# AC-10: the entry skill prefixes the prompt; the brief path is absolute
# --------------------------------------------------------------------------
ac_10_prompt_skill_and_brief() {
  mkdir -p "$TC/code/org"
  mk_std_repo "$TC/code/org/primary"
  printf '# brief\n' >"$TC/brief.md"

  run_dispatch --slug ac10a --brief "$TC/brief.md" --target primary
  assert_zero "$DRC" "default-skill dispatch exit status (stderr: $(flat "$DERR"))"
  if load_dispatch_argv "$(wt_path "$TC/code/org/primary" ac10a)" "default skill"; then
    assert_starts_with "$(argv_at 0)" "/superpowers:brainstorming " "default entry skill"
    assert_contains "$(argv_at 0)" "$TC/docs/dispatch/brief.md" \
      "absolute staged brief path in the prompt"
  fi

  run_dispatch --slug ac10b --brief "$TC/brief.md" --target primary \
    --skill superpowers:systematic-debugging
  assert_zero "$DRC" "--skill dispatch exit status (stderr: $(flat "$DERR"))"
  if load_dispatch_argv "$(wt_path "$TC/code/org/primary" ac10b)" "overridden skill"; then
    assert_starts_with "$(argv_at 0)" "/superpowers:systematic-debugging " \
      "--skill overrides the prompt prefix"
    assert_not_contains "$(argv_at 0)" "/superpowers:brainstorming" \
      "the default skill must not survive --skill"
    assert_contains "$(argv_at 0)" "$TC/docs/dispatch/brief.md" \
      "absolute staged brief path in the prompt"
  fi
}

# --------------------------------------------------------------------------
# AC-11: one dispatch produces exactly one window, named <primary>-<slug>
# --------------------------------------------------------------------------
ac_11_single_window_named() {
  mkdir -p "$TC/code/org"
  mk_std_repo "$TC/code/org/primary"
  printf '# brief\n' >"$TC/brief.md"

  local before after delta
  before="$(tmux_window_count)"

  run_dispatch --slug ac11 --brief "$TC/brief.md" --target primary
  assert_zero "$DRC" "dispatch exit status (stderr: $(flat "$DERR"))"

  # A failed dispatch launched nothing, so only a successful one is worth waiting on.
  if [ "$DRC" -eq 0 ]; then
    poll_for_window "primary-ac11" || true
  fi

  local names
  names="$(tmux -L "$SOCK" list-windows -a -F '#{window_name}' 2>/dev/null | tr '\n' ' ')"
  assert_contains " $names" " primary-ac11 " "a tmux window named primary-ac11 exists"

  after="$(tmux_window_count)"
  delta=$((after - before))
  assert_eq "$delta" "1" "tmux window count delta ($before -> $after)"
}

# --------------------------------------------------------------------------
# AC-12: the report names window, worktrees, session id, transcript, cleanup
# --------------------------------------------------------------------------
ac_12_report_fields() {
  mkdir -p "$TC/code/org"
  mk_std_repo "$TC/code/org/primary"
  mk_std_repo "$TC/code/org/second"
  printf '# brief\n' >"$TC/brief.md"

  run_dispatch --slug ac12 --brief "$TC/brief.md" --target primary --target second
  assert_zero "$DRC" "dispatch exit status (stderr: $(flat "$DERR"))"

  assert_contains "$DOUT" "primary-ac12" "stdout names the window"
  assert_contains "$DOUT" "$(wt_path "$TC/code/org/primary" ac12)" "stdout names the primary worktree"
  assert_contains "$DOUT" "$(wt_path "$TC/code/org/second" ac12)" "stdout names the second worktree"
  assert_contains "$DOUT" "--cleanup ac12" "stdout shows the cleanup invocation"

  if load_dispatch_argv "$(wt_path "$TC/code/org/primary" ac12)" "report cross-check"; then
    local sid_idx uuid
    sid_idx="$(argv_index_of "--session-id")"
    if [ "$sid_idx" -ge 0 ]; then
      uuid="$(argv_at $((sid_idx + 1)))"
      assert_contains "$DOUT" "$uuid" "stdout reports the session id that was passed"
      assert_match "$DOUT" "\.claude/projects/[^[:space:]]+/${uuid}\.jsonl" \
        "stdout reports the transcript path"
    else
      fail "no --session-id in recorded argv, so the reported id cannot be cross-checked"
    fi
  fi
}

# --------------------------------------------------------------------------
# AC-13: base ref auto-detection, with --base overriding
# --------------------------------------------------------------------------
ac_13_base_ref_resolution() {
  mkdir -p "$TC/code/org"
  printf '# brief\n' >"$TC/brief.md"

  # (a) origin/HEAD present -> origin/main, not the unpushed local tip
  local alpha="$TC/code/org/alpha"
  mk_std_repo "$alpha" main
  add_local_commit "$alpha" "unpushed alpha work"
  local alpha_origin alpha_local
  alpha_origin="$(git -C "$alpha" rev-parse origin/main)"
  alpha_local="$(git -C "$alpha" rev-parse main)"
  assert_ne "$alpha_local" "$alpha_origin" "fixture sanity: local main is ahead of origin/main"

  run_dispatch --slug ac13a --brief "$TC/brief.md" --target alpha
  assert_zero "$DRC" "origin/HEAD dispatch exit status (stderr: $(flat "$DERR"))"
  assert_eq "$(git -C "$(wt_path "$alpha" ac13a)" rev-parse HEAD 2>/dev/null || printf '<no worktree>')" \
    "$alpha_origin" "origin/HEAD resolves to origin/main"

  # (b) origin/HEAD deleted, only origin/master remains
  local beta="$TC/code/org/beta"
  mk_std_repo "$beta" master
  git -C "$beta" symbolic-ref -d refs/remotes/origin/HEAD >/dev/null 2>&1
  add_local_commit "$beta" "unpushed beta work"
  local beta_origin
  beta_origin="$(git -C "$beta" rev-parse origin/master)"

  run_dispatch --slug ac13b --brief "$TC/brief.md" --target beta
  assert_zero "$DRC" "origin/master fallback exit status (stderr: $(flat "$DERR"))"
  assert_eq "$(git -C "$(wt_path "$beta" ac13b)" rev-parse HEAD 2>/dev/null || printf '<no worktree>')" \
    "$beta_origin" "falls back to origin/master"

  # (c) --base is honoured over auto-detection
  local gamma="$TC/code/org/gamma"
  mk_std_repo "$gamma" main
  git -C "$gamma" checkout -q -b legacy
  add_local_commit "$gamma" "legacy branch work"
  git -C "$gamma" push -q -u origin legacy
  git -C "$gamma" checkout -q main
  local gamma_legacy
  gamma_legacy="$(git -C "$gamma" rev-parse origin/legacy)"
  assert_ne "$gamma_legacy" "$(git -C "$gamma" rev-parse origin/main)" \
    "fixture sanity: origin/legacy differs from origin/main"

  run_dispatch --slug ac13c --brief "$TC/brief.md" --target gamma --base origin/legacy
  assert_zero "$DRC" "--base dispatch exit status (stderr: $(flat "$DERR"))"
  assert_eq "$(git -C "$(wt_path "$gamma" ac13c)" rev-parse HEAD 2>/dev/null || printf '<no worktree>')" \
    "$gamma_legacy" "--base origin/legacy is honoured"

  # (d) no remote and no --base is a hard error naming --base
  local delta="$TC/code/org/delta"
  mk_repo "$delta" main
  run_dispatch --slug ac13d --brief "$TC/brief.md" --target delta
  assert_nonzero "$DRC" "no-remote dispatch exit status"
  assert_contains "$DERR" "--base" "no-remote stderr must name --base"
  assert_absent "$(wt_path "$delta" ac13d)" "no worktree when the base cannot be resolved"
}

# --------------------------------------------------------------------------
# AC-14: cleanup removes the worktree and the dispatch branch
# --------------------------------------------------------------------------
ac_14_cleanup_removes() {
  mkdir -p "$TC/code/org"
  mk_std_repo "$TC/code/org/primary"
  printf '# brief\n' >"$TC/brief.md"

  run_dispatch --slug ac14 --brief "$TC/brief.md" --target primary
  assert_zero "$DRC" "setup dispatch exit status (stderr: $(flat "$DERR"))"
  local wt
  wt="$(wt_path "$TC/code/org/primary" ac14)"
  poll_for_dispatch_argv "$wt" || true

  run_dispatch --cleanup ac14 --target primary
  assert_zero "$DRC" "cleanup exit status (stderr: $(flat "$DERR"))"
  assert_absent "$wt" "the worktree directory after cleanup"

  local branches
  branches="$(git -C "$TC/code/org/primary" branch --format='%(refname:short)' 2>/dev/null | tr '\n' ' ')"
  assert_not_contains "$branches" "dispatch/ac14" "dispatch branch after cleanup"
}

# --------------------------------------------------------------------------
# AC-15: cleanup refuses a dirty worktree unless forced
# --------------------------------------------------------------------------
ac_15_cleanup_refuses_dirty() {
  mkdir -p "$TC/code/org"
  mk_std_repo "$TC/code/org/primary"
  printf '# brief\n' >"$TC/brief.md"

  run_dispatch --slug ac15 --brief "$TC/brief.md" --target primary
  assert_zero "$DRC" "setup dispatch exit status (stderr: $(flat "$DERR"))"
  local wt
  wt="$(wt_path "$TC/code/org/primary" ac15)"
  poll_for_dispatch_argv "$wt" || true
  if [ ! -d "$wt" ]; then
    fail "setup dispatch produced no worktree at $wt, so cleanup cannot be exercised"
    return 0
  fi
  printf 'uncommitted work\n' >>"$wt/README.md"

  run_dispatch --cleanup ac15 --target primary
  assert_nonzero "$DRC" "cleanup of a dirty worktree must be refused"
  assert_contains "$DERR" "uncommitted changes" "dirty-refusal stderr"
  assert_dir "$wt" "a refused cleanup must leave the worktree in place"

  run_dispatch --cleanup ac15 --target primary --force
  assert_zero "$DRC" "forced cleanup exit status (stderr: $(flat "$DERR"))"
  assert_absent "$wt" "the worktree directory after a forced cleanup"
}

# --------------------------------------------------------------------------
# AC-16: cleanup refuses unmerged commits
# --------------------------------------------------------------------------
ac_16_cleanup_refuses_unmerged() {
  mkdir -p "$TC/code/org"
  mk_std_repo "$TC/code/org/primary"
  printf '# brief\n' >"$TC/brief.md"

  run_dispatch --slug ac16 --brief "$TC/brief.md" --target primary
  assert_zero "$DRC" "setup dispatch exit status (stderr: $(flat "$DERR"))"
  local wt
  wt="$(wt_path "$TC/code/org/primary" ac16)"
  poll_for_dispatch_argv "$wt" || true
  if [ ! -d "$wt" ]; then
    fail "setup dispatch produced no worktree at $wt, so cleanup cannot be exercised"
    return 0
  fi
  printf 'committed work\n' >>"$wt/README.md"
  git -C "$wt" commit -qam "work beyond the base ref"

  run_dispatch --cleanup ac16 --target primary
  assert_nonzero "$DRC" "cleanup with unmerged commits must be refused"
  assert_contains "$DERR" "not in origin/main" "unmerged-refusal stderr"
  assert_dir "$wt" "a refused cleanup must leave the worktree in place"
}

# --------------------------------------------------------------------------
# AC-17: the installer exposes the tool at the documented paths
# --------------------------------------------------------------------------
ac_17_install_symlinks_work() {
  local home="$TC/home"
  mkdir -p "$home"

  RUN_ENV=("HOME=$home")
  run_capture "$INSTALLER"
  assert_zero "$RC" "install.sh exit status (stderr: $(flat "$ERR"))"

  local script="$home/.claude/scripts/dispatch-task.sh"
  local command_md="$home/.claude/commands/dispatch.md"

  [ -L "$script" ] || fail "expected a symlink at $script"
  [ -L "$command_md" ] || fail "expected a symlink at $command_md"

  RUN_ENV=("HOME=$home")
  run_capture "$script" --help
  assert_zero "$RC" "--help through the symlink (stderr: $(flat "$ERR"))"
  assert_match "$OUT" '[Uu]sage' "--help prints usage through the symlink"

  local allowed
  allowed="$(grep -i 'allowed-tools' "$command_md" 2>/dev/null | tr '\n' ' ')"
  assert_contains "$allowed" "dispatch-task.sh" \
    "commands/dispatch.md has an allowed-tools line naming the script"
}

# --------------------------------------------------------------------------
# AC-18: regression guard - installing must not disturb unrelated tooling
# --------------------------------------------------------------------------
ac_18_install_preserves_unrelated_tooling() {
  local home="$TC/home"
  mkdir -p "$home/.claude/scripts" "$home/.claude/commands"

  # A synthetic neighbour rather than whatever happens to sit in the real
  # ~/.claude. The property under test is that install.sh leaves other files
  # alone, and it has to hold on any machine - including one whose ~/.claude
  # holds nothing else at all.
  local other_sh="$home/.claude/scripts/other-tool.sh"
  local other_md="$home/.claude/commands/other-tool.md"
  cat >"$other_sh" <<'EOF'
#!/usr/bin/env bash
printf 'Usage: other-tool.sh ARG\n' >&2
exit 2
EOF
  chmod +x "$other_sh"
  cat >"$other_md" <<'EOF'
---
description: "An unrelated command predating the dispatch install"
---
EOF

  local sh_before md_before
  sh_before="$(sha256sum <"$other_sh")"
  md_before="$(sha256sum <"$other_md")"

  RUN_ENV=("HOME=$home")
  run_capture "$INSTALLER"
  assert_zero "$RC" "install.sh exit status (stderr: $(flat "$ERR"))"

  assert_eq "$(sha256sum <"$other_sh" 2>/dev/null || printf 'MISSING')" "$sh_before" \
    "other-tool.sh must be byte-identical after install"
  assert_eq "$(sha256sum <"$other_md" 2>/dev/null || printf 'MISSING')" "$md_before" \
    "other-tool.md must be byte-identical after install"

  # Still functional: with no arguments it refuses and shows its usage.
  RUN_ENV=("HOME=$home")
  run_capture "$other_sh"
  assert_nonzero "$RC" "other-tool.sh with no arguments"
  assert_match "$OUT$ERR" '[Uu]sage' "other-tool.sh still prints its usage"

  # The neighbour surviving is only half the requirement: the install itself
  # must still have landed beside it.
  [ -L "$home/.claude/scripts/dispatch-task.sh" ] ||
    fail "install.sh must still create its own symlink alongside unrelated files"
}

# --------------------------------------------------------------------------
# AC-19: the herdr backend dispatches with the same argv contract as tmux
#
# herdr's `pane run` evaluates a joined string in the pane's shell rather than
# execing argv, which is the one place the two backends could diverge: an
# unquoted prompt splits into a word per argument and the session comes up with
# a broken brief. The stub evals the same way the real client does, so this
# pins the quoting rather than trusting it.
# --------------------------------------------------------------------------
ac_19_herdr_backend_launches() {
  mkdir -p "$TC/code/org"
  mk_std_repo "$TC/code/org/primary"
  printf '# brief\n' >"$TC/brief.md"

  run_dispatch_herdr --slug ac19 --brief "$TC/brief.md" --target primary
  assert_zero "$DRC" "herdr dispatch exit status (stderr: $(flat "$DERR"))"

  local wt
  wt="$(wt_path "$TC/code/org/primary" ac19)"
  assert_dir "$wt" "the herdr backend still creates the primary worktree"

  poll_for_dispatch_argv "$wt" || { fail "no argv recorded under the herdr backend"; return 0; }
  read_argv "$wt/.dispatch-argv"
  assert_eq "$(argv_at 0)" \
    "/superpowers:brainstorming Read $TC/docs/dispatch/brief.md — it is your briefing. Follow it. Store every durable brief, design, review, and research artifact under $TC/docs, never in a target repository's docs directory." \
    "the whole prompt must survive herdr's shell as a single argument"
  assert_eq "$(argv_at 1)" "--session-id" "session flag follows the prompt"

  # The tab is opened where the work is, and labelled like the tmux window.
  assert_eq "$(cat "$TC/herdr-state/tab-cwd" 2>/dev/null)" "$wt" "tab cwd"
  assert_eq "$(cat "$TC/herdr-state/tab-label" 2>/dev/null)" "primary-ac19" "tab label"

  # ...and in the workspace the dispatch was fired FROM. Without this, herdr
  # falls back to the workspace it is focused on, which is wherever the operator
  # happens to be looking rather than where the work is.
  assert_eq "$(cat "$TC/herdr-state/tab-workspace" 2>/dev/null)" "w9" \
    "the tab must land in the caller's workspace, not herdr's focused one"

  # The report has to tell the operator how to reach it in herdr terms.
  assert_contains "$DOUT" "mux:" "report names the backend"
  assert_contains "$DOUT" "herdr tab focus" "report gives a herdr focus command"
  assert_not_contains "$DOUT" "tmux select-window" "report must not give tmux advice under herdr"
}

# --------------------------------------------------------------------------
# AC-20: workspace placement degrades and overrides cleanly
#
# The workspace is inherited from the environment, so both ends of that need
# pinning: dispatch run from a shell herdr did not start has no workspace to
# inherit and must fall back to herdr's own choice rather than passing an empty
# --workspace, and an operator who wants the tab somewhere else must be able to
# say so without editing the launcher.
# --------------------------------------------------------------------------
ac_20_herdr_workspace_fallback_and_override() {
  mkdir -p "$TC/code/org"
  mk_std_repo "$TC/code/org/primary"
  printf '# brief\n' >"$TC/brief.md"

  # No HERDR_WORKSPACE_ID: no --workspace flag at all, and the dispatch still
  # works. An empty string here would be a flag with no value, which the real
  # client rejects.
  run_dispatch_herdr_no_workspace --slug ac20a --brief "$TC/brief.md" --target primary
  assert_zero "$DRC" "herdr dispatch with no caller workspace (stderr: $(flat "$DERR"))"
  assert_eq "$(cat "$TC/herdr-state/tab-workspace" 2>/dev/null)" "" \
    "with nothing to inherit, no workspace is named and herdr decides"

  # DISPATCH_HERDR_WORKSPACE beats the inherited value.
  ACC_HERDR_ENV=1 ACC_HERDR_WORKSPACE="w9" \
    DISPATCH_HERDR_WORKSPACE="w3" _dispatch "" \
    --slug ac20b --brief "$TC/brief.md" --target primary
  assert_zero "$DRC" "herdr dispatch with an overridden workspace (stderr: $(flat "$DERR"))"
  assert_eq "$(cat "$TC/herdr-state/tab-workspace" 2>/dev/null)" "w3" \
    "DISPATCH_HERDR_WORKSPACE must beat the inherited HERDR_WORKSPACE_ID"
}

# --------------------------------------------------------------------------
# Runner
# --------------------------------------------------------------------------

run_case() {
  local name="$1"
  CASE_FAILED=0
  RUN_ENV=()
  ARGV=()
  TC="$(mktemp -d "$RUNDIR/case.XXXXXX")"
  printf '%s\n' "$name"
  "$name"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$CASE_FAILED" -ne 0 ]; then
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  RESULT: FAIL\n'
  else
    printf '  RESULT: pass\n'
  fi
  rm -rf "$TC"
  TC=""
}

main() {
  local requested="${1:-}" selected=("${CASES[@]}") name

  if [ -n "$requested" ]; then
    case " ${CASES[*]} " in
      *" $requested "*) selected=("$requested") ;;
      *)
        printf 'acceptance: unknown case %s\n' "$requested" >&2
        printf 'acceptance: known cases are:\n' >&2
        printf '  %s\n' "${CASES[@]}" >&2
        return 2
        ;;
    esac
  fi

  RUNDIR="$(mktemp -d "${TMPDIR:-/tmp}/dispatch-acc.XXXXXX")"
  mkfifo "$RUNDIR/tick"
  exec 9<>"$RUNDIR/tick"
  trap teardown_run EXIT

  if ! tmux_start; then
    printf 'acceptance: could not start the private tmux server on %s\n' "$SOCK" >&2
    return 2
  fi

  printf 'acceptance gate: %s\n' "$ROOT"
  printf 'entrypoint: %s\n' "$ENTRYPOINT"
  printf 'stub:       %s\n' "$STUB"
  printf 'tmux:       -L %s\n\n' "$SOCK"

  for name in "${selected[@]}"; do
    run_case "$name"
  done

  printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ]
}

main "$@"
