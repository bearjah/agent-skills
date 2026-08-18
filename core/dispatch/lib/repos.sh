#!/usr/bin/env bash
# Repo name resolution.

# resolve_repo <name-or-abs-path>
# Prints the absolute repo path. Returns 1 with a stderr message otherwise.
resolve_repo() {
  local input="$1" matches=() d glob
  glob="${DISPATCH_SEARCH_GLOB:-$HOME/code/*}"

  if [[ "$input" == /* ]]; then
    if git -C "$input" rev-parse --git-dir >/dev/null 2>&1; then
      printf '%s\n' "$input"
      return 0
    fi
    printf 'dispatch: not a git repo: %s\n' "$input" >&2
    return 1
  fi

  # Intentionally unquoted: $glob must undergo pathname expansion.
  # shellcheck disable=SC2086
  for d in $glob; do
    if [ -d "$d/$input" ] && git -C "$d/$input" rev-parse --git-dir >/dev/null 2>&1; then
      matches+=("$d/$input")
    fi
  done

  case "${#matches[@]}" in
    1) printf '%s\n' "${matches[0]}" ;;
    0) printf 'dispatch: no repo named %s under %s\n' "$input" "$glob" >&2; return 1 ;;
    *) { printf 'dispatch: ambiguous repo name %s, candidates:\n' "$input"
         printf '  %s\n' "${matches[@]}"; } >&2
       return 1 ;;
  esac
}

# detect_base <abs-repo-path>
# Prints the base ref to branch from. Returns 1 if it cannot be determined.
detect_base() {
  local repo="$1" head candidate
  if head="$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    printf '%s\n' "$head"
    return 0
  fi
  for candidate in origin/main origin/master; do
    if git -C "$repo" rev-parse --verify --quiet "refs/remotes/$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf 'dispatch: cannot determine default branch for %s; pass --base explicitly\n' \
    "$repo" >&2
  return 1
}
