#!/usr/bin/env bash
# Shared durable-document location for every adapter and workflow.

agent_docs_root() {
  local root="${AGENT_DOCS_ROOT:-$HOME/docs}"
  case "$root" in
    '~') root="$HOME" ;;
    '~/'*) root="$HOME/${root#\~/}" ;;
  esac
  case "$root" in
    /*) printf '%s\n' "$root" ;;
    *) printf 'docs: AGENT_DOCS_ROOT must be an absolute path: %s\n' "$root" >&2; return 1 ;;
  esac
}

ensure_agent_docs_root() {
  local root="$1"
  mkdir -p "$root/dispatch" "$root/designs" "$root/reviews" "$root/research"
}

stage_dispatch_brief() {
  local root="$1" brief="$2" dispatch_root source_path destination
  dispatch_root="$(readlink -f "$root/dispatch")" || return 1
  source_path="$(readlink -f "$brief")" || return 1
  case "$source_path" in
    "$dispatch_root"/*) printf '%s\n' "$source_path"; return 0 ;;
  esac

  destination="$dispatch_root/$(basename "$brief")"
  if [ -e "$destination" ]; then
    if cmp -s "$source_path" "$destination"; then
      printf '%s\n' "$destination"
      return 0
    fi
    printf 'docs: dispatch brief already exists with different content: %s\n' "$destination" >&2
    return 1
  fi
  cp -- "$source_path" "$destination" || return 1
  printf '%s\n' "$destination"
}
