#!/usr/bin/env bash
# Worktree lifecycle. Layout is sibling-style: <parent>/<repo>-wt-<slug>.

worktree_path() {
  local repo="$1" slug="$2"
  printf '%s/%s-wt-%s\n' "$(dirname "$repo")" "$(basename "$repo")" "$slug"
}

create_worktree() {
  local repo="$1" slug="$2" base="$3" wt
  wt="$(worktree_path "$repo" "$slug")"
  git -C "$repo" worktree add -b "dispatch/$slug" "$wt" "$base" >/dev/null 2>&1 || {
    printf 'dispatch: failed to create worktree %s from %s\n' "$wt" "$base" >&2
    return 1
  }
  printf '%s\n' "$wt"
}

worktree_is_dirty() {
  [ -n "$(git -C "$1" status --porcelain)" ]
}

worktree_has_unmerged() {
  local wt="$1" base="$2"
  [ -n "$(git -C "$wt" log --oneline "$base..HEAD" 2>/dev/null)" ]
}

# remove_worktree <repo> <slug> <base> <force:0|1>
remove_worktree() {
  local repo="$1" slug="$2" base="$3" force="$4" wt
  wt="$(worktree_path "$repo" "$slug")"

  if [ ! -d "$wt" ]; then
    printf 'dispatch: no worktree at %s\n' "$wt" >&2
    return 1
  fi

  if [ "$force" -ne 1 ]; then
    if worktree_is_dirty "$wt"; then
      printf 'dispatch: %s has uncommitted changes; use --force to discard\n' "$wt" >&2
      return 1
    fi
    if worktree_has_unmerged "$wt" "$base"; then
      printf 'dispatch: %s has commits not in %s; use --force to discard\n' "$wt" "$base" >&2
      return 1
    fi
  fi

  git -C "$repo" worktree remove --force "$wt" || return 1
  git -C "$repo" branch -D "dispatch/$slug" >/dev/null 2>&1 || true
}
