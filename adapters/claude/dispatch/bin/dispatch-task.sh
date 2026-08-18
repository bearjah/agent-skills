#!/usr/bin/env bash
# Dispatch a briefed session into an isolated worktree in a new tmux window.
set -euo pipefail

# Resolve the real path first: the supported entrypoint is a symlink at
# ~/.claude/scripts/dispatch-task.sh, and bash reports BASH_SOURCE as the link,
# not its target, so the libraries would be looked for beside the link.
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# The shared lifecycle is portable; this adapter supplies Claude's state root.
export DISPATCH_WORKTREE_ROOT="${DISPATCH_WORKTREE_ROOT:-$HOME/.claude/worktrees}"
# shellcheck source=../../../core/dispatch/lib/repos.sh
source "$REPO_ROOT/core/dispatch/lib/repos.sh"
# shellcheck source=../../../core/dispatch/lib/worktree.sh
source "$REPO_ROOT/core/dispatch/lib/worktree.sh"
# shellcheck source=../../../core/dispatch/lib/docs.sh
source "$REPO_ROOT/core/dispatch/lib/docs.sh"
# shellcheck source=lib/launch.sh
source "$HERE/lib/launch.sh"

usage() {
  cat <<'EOF'
Usage:
  dispatch-task.sh --slug SLUG --brief PATH --target REPO [--target REPO ...]
                   [--ref REPO ...] [--base REF] [--skill NAME]
                   [--permission-mode MODE]
  dispatch-task.sh --cleanup SLUG [--target REPO ...] [--base REF] [--force]

  --target   Repo the task may write to. Gets a worktree. First one is primary
             and becomes the session's cwd.
  --ref      Read-only repo, passed via --add-dir as its existing checkout.
  --base     Base ref for worktrees. Default: auto-detected per repo.
  --skill    Entry skill. Default: superpowers:brainstorming
  --permission-mode
             Permission mode for the spawned session. Default: auto.
             One of: auto acceptEdits bypassPermissions manual dontAsk plan.
             Pass "" to defer to the CLI and your settings.
EOF
}

die() { printf 'dispatch: %s\n' "$1" >&2; exit 1; }

SLUG=""
BRIEF=""
BASE=""
SKILL="superpowers:brainstorming"
# A dispatched session is unattended until you switch to it, so default to
# auto rather than leaving it blocked on the first permission prompt.
PERMISSION_MODE="auto"
CLEANUP=""
FORCE=0
TARGETS=()
REFS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --slug)    SLUG="${2:?--slug needs a value}"; shift 2 ;;
    --brief)   BRIEF="${2:?--brief needs a value}"; shift 2 ;;
    --target)  TARGETS+=("${2:?--target needs a value}"); shift 2 ;;
    --ref)     REFS+=("${2:?--ref needs a value}"); shift 2 ;;
    --base)    BASE="${2:?--base needs a value}"; shift 2 ;;
    --skill)   SKILL="${2:?--skill needs a value}"; shift 2 ;;
    --permission-mode)
               PERMISSION_MODE="${2-}"
               [ "$#" -ge 2 ] || die "--permission-mode needs a value"
               shift 2 ;;
    --cleanup) CLEANUP="${2:?--cleanup needs a value}"; shift 2 ;;
    --force)   FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)         usage >&2; die "unknown argument: $1" ;;
  esac
done

# --- resolve repos (shared by dispatch and cleanup) ---
resolved_targets=()
for t in ${TARGETS+"${TARGETS[@]}"}; do
  resolved_targets+=("$(resolve_repo "$t")")
done
resolved_refs=()
for r in ${REFS+"${REFS[@]}"}; do
  resolved_refs+=("$(resolve_repo "$r")")
done

base_for() {
  local repo="$1"
  if [ -n "$BASE" ]; then printf '%s\n' "$BASE"; else detect_base "$repo"; fi
}

if [ -n "$CLEANUP" ]; then
  [ "${#resolved_targets[@]}" -gt 0 ] || die "--cleanup needs at least one --target"
  rc=0
  for repo in "${resolved_targets[@]}"; do
    if remove_worktree "$repo" "$CLEANUP" "$(base_for "$repo")" "$FORCE"; then
      printf 'removed %s\n' "$(worktree_path "$repo" "$CLEANUP")"
    else
      rc=1
    fi
  done
  exit "$rc"
fi

# --- preflight ---
MUX="$(detect_mux)" \
  || die "unsupported DISPATCH_MUX: ${DISPATCH_MUX:-} (want one of: tmux herdr)"
case "$MUX" in
  none)
    die "no supported terminal multiplexer detected; run inside tmux or herdr, or set DISPATCH_MUX" ;;
  herdr)
    command -v "${DISPATCH_HERDR_BIN:-herdr}" >/dev/null 2>&1 \
      || die "HERDR_ENV is set but ${DISPATCH_HERDR_BIN:-herdr} is not on PATH"
    # herdr answers in JSON and the pane id has to be read back out of it.
    command -v python3 >/dev/null 2>&1 \
      || die "the herdr backend needs python3 to read herdr's JSON replies" ;;
esac
[ -n "$SLUG" ]     || die "--slug is required"
[ -n "$BRIEF" ]    || die "--brief is required"
[ -f "$BRIEF" ]    || die "brief not found: $BRIEF"
[ "${#resolved_targets[@]}" -gt 0 ] || die "at least one --target is required"

# Catch a typo here rather than after the worktrees exist; the CLI would only
# reject it once the window had already been created.
if [ -n "$PERMISSION_MODE" ]; then
  case "$PERMISSION_MODE" in
    auto|acceptEdits|bypassPermissions|manual|dontAsk|plan) ;;
    *) die "unknown permission mode: $PERMISSION_MODE (want one of: auto acceptEdits bypassPermissions manual dontAsk plan)" ;;
  esac
fi

docs_root="$(agent_docs_root)" || die "could not resolve AGENT_DOCS_ROOT"
ensure_agent_docs_root "$docs_root" || die "could not create docs root: $docs_root"

for repo in "${resolved_targets[@]}"; do
  wt="$(worktree_path "$repo" "$SLUG")"
  [ ! -e "$wt" ] || die "worktree path already exists: $wt"
  if git -C "$repo" rev-parse --verify --quiet "refs/heads/dispatch/$SLUG" >/dev/null 2>&1; then
    die "branch dispatch/$SLUG already exists in $repo"
  fi
  base_for "$repo" >/dev/null
done
BRIEF="$(stage_dispatch_brief "$docs_root" "$BRIEF")" || die "could not store dispatch brief under $docs_root/dispatch"

# --- create worktrees ---
target_worktrees=()
for repo in "${resolved_targets[@]}"; do
  git -C "$repo" fetch origin --quiet 2>/dev/null \
    || printf 'dispatch: fetch failed for %s, using local refs\n' "$repo" >&2
  target_worktrees+=("$(create_worktree "$repo" "$SLUG" "$(base_for "$repo")")")
done

primary_wt="${target_worktrees[0]}"
add_dirs=("$docs_root" "${target_worktrees[@]:1}")
for r in ${resolved_refs+"${resolved_refs[@]}"}; do
  add_dirs+=("$r")
done

# --- launch ---
session_id="$(uuidgen)"
window_name="$(basename "${resolved_targets[0]}")-$SLUG"
prompt="/$SKILL Read $BRIEF — it is your briefing. Follow it. Store every durable brief, design, review, and research artifact under $docs_root, never in a target repository's docs directory."

build_claude_argv "$prompt" "$session_id" "$PERMISSION_MODE" ${add_dirs+"${add_dirs[@]}"}
CLAUDE_ARGV=(env "AGENT_DOCS_ROOT=$docs_root" "${CLAUDE_ARGV[@]}")
launch_window "$MUX" "$window_name" "$primary_wt" "${CLAUDE_ARGV[@]}"

project_slug="$(printf '%s' "$primary_wt" | tr '/.' '--')"
cat <<EOF
dispatched: $window_name
  mux:        $MUX
  cwd:        $primary_wt
  worktrees:  ${target_worktrees[*]}
  add-dir:    ${add_dirs[*]:-<none>}
  session:    $session_id
  transcript: ~/.claude/projects/$project_slug/$session_id.jsonl
  switch:     $LAUNCH_SWITCH_HINT
  cleanup:    dispatch-task.sh --cleanup $SLUG ${TARGETS[*]/#/--target }
EOF
