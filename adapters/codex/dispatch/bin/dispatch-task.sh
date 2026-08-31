#!/usr/bin/env bash
# Dispatch a Codex session into an isolated worktree in a new multiplexer window.
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# Keep each project's dispatched worktrees with the directory the dispatch was
# invoked from. An explicit override still supports shared or custom roots.
export DISPATCH_WORKTREE_ROOT="${DISPATCH_WORKTREE_ROOT:-$PWD/.codex/worktrees}"
source "$REPO_ROOT/core/dispatch/lib/repos.sh"
source "$REPO_ROOT/core/dispatch/lib/worktree.sh"
source "$REPO_ROOT/core/dispatch/lib/docs.sh"
source "$HERE/lib/launch.sh"

usage() {
  cat <<'EOF'
Usage:
  dispatch-task.sh --slug SLUG --brief PATH --target REPO [--target REPO ...]
                   [--ref REPO ...] [--base REF] [--skill NAME]
                   [--approval-policy POLICY] [--sandbox MODE]
  dispatch-task.sh --cleanup SLUG --target REPO [--target REPO ...] [--base REF] [--force]
EOF
}

die() { printf 'dispatch: %s\n' "$1" >&2; exit 1; }
SLUG="" BRIEF="" BASE="" SKILL="" CLEANUP="" FORCE=0
APPROVAL_POLICY="${DISPATCH_CODEX_APPROVAL_POLICY:-}"
SANDBOX_MODE="${DISPATCH_CODEX_SANDBOX:-}"
TARGETS=() REFS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --slug) SLUG="${2:?--slug needs a value}"; shift 2 ;;
    --brief) BRIEF="${2:?--brief needs a value}"; shift 2 ;;
    --target) TARGETS+=("${2:?--target needs a value}"); shift 2 ;;
    --ref) REFS+=("${2:?--ref needs a value}"); shift 2 ;;
    --base) BASE="${2:?--base needs a value}"; shift 2 ;;
    --skill) SKILL="${2:?--skill needs a value}"; shift 2 ;;
    --approval-policy) APPROVAL_POLICY="${2:?--approval-policy needs a value}"; shift 2 ;;
    --sandbox) SANDBOX_MODE="${2:?--sandbox needs a value}"; shift 2 ;;
    --cleanup) CLEANUP="${2:?--cleanup needs a value}"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

resolved_targets=()
for target in ${TARGETS+"${TARGETS[@]}"}; do resolved_targets+=("$(resolve_repo "$target")"); done
resolved_refs=()
for ref in ${REFS+"${REFS[@]}"}; do resolved_refs+=("$(resolve_repo "$ref")"); done
base_for() { [ -n "$BASE" ] && printf '%s\n' "$BASE" || detect_base "$1"; }

if [ -n "$CLEANUP" ]; then
  [ "${#resolved_targets[@]}" -gt 0 ] || die "--cleanup needs at least one --target"
  rc=0
  for repo in "${resolved_targets[@]}"; do
    remove_worktree "$repo" "$CLEANUP" "$(base_for "$repo")" "$FORCE" || rc=1
  done
  exit "$rc"
fi

MUX="$(detect_mux)" \
  || die "unsupported DISPATCH_MUX: ${DISPATCH_MUX:-} (want one of: tmux herdr)"
case "$MUX" in
  none)
    die "no supported terminal multiplexer detected; run inside tmux or herdr, or set DISPATCH_MUX" ;;
  herdr)
    command -v "${DISPATCH_HERDR_BIN:-herdr}" >/dev/null 2>&1 \
      || die "HERDR_ENV is set but ${DISPATCH_HERDR_BIN:-herdr} is not on PATH"
    command -v python3 >/dev/null 2>&1 \
      || die "the herdr backend needs python3 to read herdr's JSON replies" ;;
esac
command -v "${DISPATCH_CODEX_BIN:-codex}" >/dev/null 2>&1 || die "codex is not on PATH"
[ -n "$SLUG" ] || die "--slug is required"
[ -f "$BRIEF" ] || die "brief not found: $BRIEF"
[ "${#resolved_targets[@]}" -gt 0 ] || die "at least one --target is required"
case "$APPROVAL_POLICY" in ""|untrusted|on-request|never) ;; *) die "invalid approval policy: $APPROVAL_POLICY" ;; esac
case "$SANDBOX_MODE" in ""|read-only|workspace-write|danger-full-access) ;; *) die "invalid sandbox mode: $SANDBOX_MODE" ;; esac

docs_root="$(agent_docs_root)" || die "could not resolve AGENT_DOCS_ROOT"
ensure_agent_docs_root "$docs_root" || die "could not create docs root: $docs_root"

for repo in "${resolved_targets[@]}"; do
  [ ! -e "$(worktree_path "$repo" "$SLUG")" ] || die "worktree path already exists"
  git -C "$repo" rev-parse --verify --quiet "refs/heads/dispatch/$SLUG" >/dev/null 2>&1 && die "branch dispatch/$SLUG already exists in $repo"
  base_for "$repo" >/dev/null
done
BRIEF="$(stage_dispatch_brief "$docs_root" "$BRIEF")" || die "could not store dispatch brief under $docs_root/dispatch"

worktrees=()
for repo in "${resolved_targets[@]}"; do
  git -C "$repo" fetch origin --quiet 2>/dev/null || true
  worktrees+=("$(create_worktree "$repo" "$SLUG" "$(base_for "$repo")")")
done

primary="${worktrees[0]}"
add_dirs=("$docs_root" "${worktrees[@]:1}")
for ref in ${resolved_refs+"${resolved_refs[@]}"}; do add_dirs+=("$ref"); done
prompt="Read $BRIEF and follow it. Store every durable brief, design, review, and research artifact under $docs_root, never in a target repository's docs directory."
[ -n "$SKILL" ] && prompt="Use the $SKILL workflow if it is available. $prompt"
argv=(env "AGENT_DOCS_ROOT=$docs_root" "${DISPATCH_CODEX_BIN:-codex}" --cd "$primary" -c 'model_reasoning_effort="high"' -c 'tui.vim_mode_default=true')
[ -n "$SANDBOX_MODE" ] && argv+=(--sandbox "$SANDBOX_MODE")
[ -n "$APPROVAL_POLICY" ] && argv+=(--ask-for-approval "$APPROVAL_POLICY")
[ "${#add_dirs[@]}" -gt 0 ] && argv+=(--add-dir "${add_dirs[@]}")
argv+=("$prompt")
window_name="$(basename "${resolved_targets[0]}")-$SLUG"
launch_window "$MUX" "$window_name" "$primary" "${argv[@]}"

printf 'dispatched: %s\n  mux: %s\n  cwd: %s\n  worktrees: %s\n  switch: %s\n' \
  "$window_name" "$MUX" "$primary" "${worktrees[*]}" "$LAUNCH_SWITCH_HINT"
