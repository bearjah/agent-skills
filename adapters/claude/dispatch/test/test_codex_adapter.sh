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
  [ ! -e "$home/.codex/worktrees" ] || fail "Codex install created a global worktree root"
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

test_codex_dispatch_defaults_worktree_root_to_pwd() {
  mkdir -p "$SANDBOX/invoker" "$SANDBOX/herdr"
  mkrepo "$SANDBOX/repo" main
  mkremote "$SANDBOX/repo"
  printf 'review brief\n' > "$SANDBOX/review.md"

  (
    cd "$SANDBOX/invoker" || exit 1
    unset DISPATCH_WORKTREE_ROOT
    TMUX='' HERDR_ENV=1 DISPATCH_MUX=herdr \
    DISPATCH_HERDR_BIN="$ROOT/test/stub/herdr" \
    DISPATCH_HERDR_STATE="$SANDBOX/herdr" \
    DISPATCH_CODEX_BIN="$ROOT/test/stub/claude" \
    AGENT_DOCS_ROOT="$SANDBOX/docs" \
      "$CODEX_ROOT/bin/dispatch-task.sh" \
        --slug local-root --brief "$SANDBOX/review.md" \
        --target "$SANDBOX/repo" >/dev/null
  ) || { fail "Codex dispatch with the default worktree root exited non-zero"; return; }

  local wt="$SANDBOX/invoker/.codex/worktrees/repo/local-root"
  [ -d "$wt" ] || { fail "Codex worktree was not created under PWD/.codex/worktrees"; return; }
  assert_eq "$(cat "$SANDBOX/herdr/tab-cwd")" "$wt" "Codex dispatched cwd"
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
  case " ${argv[*]} " in
    *" --sandbox "*) fail "Codex dispatch overrode the configured sandbox by default" ;;
  esac
  case " ${argv[*]} " in
    *" --ask-for-approval "*) fail "Codex dispatch overrode the configured approval policy by default" ;;
  esac
  assert_contains "${argv[*]}" "tui.vim_mode_default=true"
  local model_index=-1 i
  for ((i=0; i<${#argv[@]}; i++)); do
    if [ "${argv[i]}" = "--model" ]; then model_index=$i; break; fi
  done
  [ "$model_index" -ge 0 ] || { fail "Codex dispatch did not pin the lead model"; return; }
  assert_eq "${argv[model_index+1]}" "gpt-6.1-sol" "Codex lead model"
  assert_contains "${argv[*]}" 'model_reasoning_effort="high"'
  local workflow_root
  workflow_root="$(cd "$ROOT/../../../core/dispatch" && pwd)"
  [ -s "$workflow_root/workflow.md" ] || fail "shared execution workflow is missing"
  assert_contains "${argv[-1]}" "$workflow_root/workflow.md"
  [ -s "$workflow_root/codex-model-policy.md" ] || fail "Codex model policy is missing"
  assert_contains "${argv[-1]}" "$workflow_root/codex-model-policy.md"
  assert_contains "${argv[-1]}" "bounded workers use gpt-6-luna/high"
  assert_contains "${argv[-1]}" "$CODEX_ROOT/bin/dispatch-task.sh"
  assert_contains "${argv[-1]}" "$SANDBOX/worktrees"
  # The workflow must be accessible even when the target checkout is elsewhere.
  local add_dirs="${argv[*]:0:$(( ${#argv[@]} - 1 ))}"
  assert_contains "$add_dirs" "$workflow_root"
}

test_codex_dispatch_allows_permission_overrides() {
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
      --slug codex-permissions --brief "$SANDBOX/review.md" \
      --target "$SANDBOX/repo" \
      --sandbox workspace-write --approval-policy on-request >/dev/null \
    || { fail "Codex dispatch exited non-zero"; return; }

  local wt="$SANDBOX/worktrees/repo/codex-permissions" argv=()
  mapfile -t argv < "$wt/.dispatch-argv"
  assert_contains "${argv[*]}" "--sandbox workspace-write"
  assert_contains "${argv[*]}" "--ask-for-approval on-request"
  assert_contains "${argv[-1]}" "Parent Codex sandbox: workspace-write; approval policy: on-request"
}

test_codex_dispatch_allows_environment_permission_overrides() {
  mkdir -p "$SANDBOX/herdr"
  mkrepo "$SANDBOX/repo" main
  mkremote "$SANDBOX/repo"
  printf 'review brief\n' > "$SANDBOX/review.md"

  TMUX='' HERDR_ENV=1 DISPATCH_MUX=herdr \
  DISPATCH_HERDR_BIN="$ROOT/test/stub/herdr" \
  DISPATCH_HERDR_STATE="$SANDBOX/herdr" \
  DISPATCH_CODEX_BIN="$ROOT/test/stub/claude" \
  DISPATCH_CODEX_SANDBOX=read-only \
  DISPATCH_CODEX_APPROVAL_POLICY=untrusted \
  DISPATCH_WORKTREE_ROOT="$SANDBOX/worktrees" \
  AGENT_DOCS_ROOT="$SANDBOX/docs" \
    "$CODEX_ROOT/bin/dispatch-task.sh" \
      --slug codex-env-permissions --brief "$SANDBOX/review.md" \
      --target "$SANDBOX/repo" >/dev/null \
    || { fail "Codex dispatch exited non-zero"; return; }

  local wt="$SANDBOX/worktrees/repo/codex-env-permissions" argv=()
  mapfile -t argv < "$wt/.dispatch-argv"
  assert_contains "${argv[*]}" "--sandbox read-only"
  assert_contains "${argv[*]}" "--ask-for-approval untrusted"
  assert_contains "${argv[-1]}" "Parent Codex sandbox: read-only; approval policy: untrusted"
}

test_codex_dispatch_rejects_invalid_sandbox_mode() {
  mkrepo "$SANDBOX/repo" main
  mkremote "$SANDBOX/repo"
  printf 'review brief\n' > "$SANDBOX/review.md"
  local out

  out="$(TMUX=fake DISPATCH_CODEX_BIN=true \
    DISPATCH_WORKTREE_ROOT="$SANDBOX/worktrees" \
    AGENT_DOCS_ROOT="$SANDBOX/docs" \
    "$CODEX_ROOT/bin/dispatch-task.sh" \
      --slug invalid-sandbox --brief "$SANDBOX/review.md" \
      --target "$SANDBOX/repo" --sandbox nonsense 2>&1)" \
    && fail "expected failure for invalid sandbox mode"

  assert_contains "$out" "invalid sandbox mode"
  [ ! -d "$SANDBOX/worktrees/repo/invalid-sandbox" ] \
    || fail "worktree created despite invalid sandbox mode"
}
