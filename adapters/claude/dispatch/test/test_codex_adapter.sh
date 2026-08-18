#!/usr/bin/env bash

CODEX_ROOT="$(cd "$ROOT/../../codex/dispatch" && pwd)"

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
}
