#!/usr/bin/env bash

# dispatch <args...> - run the entrypoint with tmux present, capturing output
dispatch() {
  "$ROOT/bin/dispatch-task.sh" "$@" 2>&1
}

# HERDR_ENV has to be cleared alongside TMUX: herdr exports it into every
# process it starts, so a suite run from inside a herdr tab would otherwise
# detect a live multiplexer here and dispatch for real.
test_preflight_requires_a_multiplexer() {
  mkrepo "$SANDBOX/r" main
  mkremote "$SANDBOX/r"
  printf 'brief\n' > "$SANDBOX/b.md"
  local out
  out="$(TMUX='' HERDR_ENV='' DISPATCH_MUX='' \
         dispatch --slug s --brief "$SANDBOX/b.md" --target "$SANDBOX/r")" \
    && fail "expected failure with no multiplexer"
  assert_contains "$out" "no supported terminal multiplexer"
  [ ! -d "$SANDBOX/r-wt-s" ] || fail "worktree created despite preflight failure"
}

test_preflight_rejects_an_unknown_mux_override() {
  mkrepo "$SANDBOX/r" main
  mkremote "$SANDBOX/r"
  printf 'brief\n' > "$SANDBOX/b.md"
  local out
  out="$(DISPATCH_MUX=screen dispatch --slug s --brief "$SANDBOX/b.md" --target "$SANDBOX/r")" \
    && fail "expected failure for an unsupported DISPATCH_MUX"
  assert_contains "$out" "unsupported DISPATCH_MUX"
  [ ! -d "$SANDBOX/r-wt-s" ] || fail "worktree created despite preflight failure"
}

test_preflight_requires_brief_file() {
  mkrepo "$SANDBOX/r" main
  mkremote "$SANDBOX/r"
  local out
  out="$(TMUX=fake dispatch --slug s --brief "$SANDBOX/missing.md" --target "$SANDBOX/r")" \
    && fail "expected failure for missing brief"
  assert_contains "$out" "brief not found"
  [ ! -d "$SANDBOX/r-wt-s" ] || fail "worktree created despite preflight failure"
}

test_preflight_requires_a_target() {
  printf 'brief\n' > "$SANDBOX/b.md"
  local out
  out="$(TMUX=fake dispatch --slug s --brief "$SANDBOX/b.md")" \
    && fail "expected failure with no target"
  assert_contains "$out" "at least one --target"
}

test_preflight_rejects_existing_worktree_path() {
  mkrepo "$SANDBOX/r" main
  mkremote "$SANDBOX/r"
  printf 'brief\n' > "$SANDBOX/b.md"
  mkdir -p "$SANDBOX/r-wt-s"
  local out
  out="$(TMUX=fake dispatch --slug s --brief "$SANDBOX/b.md" --target "$SANDBOX/r")" \
    && fail "expected failure for existing worktree path"
  assert_contains "$out" "already exists"
}

test_preflight_rejects_existing_branch() {
  mkrepo "$SANDBOX/r" main
  mkremote "$SANDBOX/r"
  printf 'brief\n' > "$SANDBOX/b.md"
  git -C "$SANDBOX/r" branch dispatch/s
  local out
  out="$(TMUX=fake dispatch --slug s --brief "$SANDBOX/b.md" --target "$SANDBOX/r")" \
    && fail "expected failure for existing branch"
  assert_contains "$out" "already exists"
}

test_preflight_rejects_invalid_permission_mode() {
  mkrepo "$SANDBOX/r" main
  mkremote "$SANDBOX/r"
  printf 'brief\n' > "$SANDBOX/b.md"
  local out
  out="$(TMUX=fake dispatch --slug s --brief "$SANDBOX/b.md" --target "$SANDBOX/r" \
        --permission-mode nonsense)" && fail "expected failure for invalid permission mode"
  assert_contains "$out" "permission mode"
  [ ! -d "$SANDBOX/r-wt-s" ] || fail "worktree created despite preflight failure"
}
