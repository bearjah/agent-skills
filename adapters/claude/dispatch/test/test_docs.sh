#!/usr/bin/env bash

DOCS_LIB="$ROOT/../../../core/dispatch/lib/docs.sh"

test_docs_root_defaults_to_home_docs() {
  local actual
  actual="$(HOME="$SANDBOX/home" AGENT_DOCS_ROOT='' bash -c 'source "$1"; agent_docs_root' _ "$DOCS_LIB")"
  assert_eq "$actual" "$SANDBOX/home/docs"
}

test_docs_root_honours_absolute_override() {
  local actual
  actual="$(HOME="$SANDBOX/home" AGENT_DOCS_ROOT="$SANDBOX/archive" bash -c 'source "$1"; agent_docs_root' _ "$DOCS_LIB")"
  assert_eq "$actual" "$SANDBOX/archive"
}

test_docs_root_rejects_relative_override() {
  HOME="$SANDBOX/home" AGENT_DOCS_ROOT="relative/docs" \
    bash -c 'source "$1"; agent_docs_root' _ "$DOCS_LIB" >/dev/null 2>&1 \
    && fail "accepted a relative AGENT_DOCS_ROOT"
}

test_docs_root_creates_every_document_category() {
  source "$DOCS_LIB"
  ensure_agent_docs_root "$SANDBOX/docs"
  local category
  for category in dispatch designs reviews research; do
    [ -d "$SANDBOX/docs/$category" ] || fail "missing docs category: $category"
  done
}

test_dispatch_brief_is_staged_under_docs_root() {
  source "$DOCS_LIB"
  ensure_agent_docs_root "$SANDBOX/docs"
  printf 'brief\n' > "$SANDBOX/source.md"
  local staged
  staged="$(stage_dispatch_brief "$SANDBOX/docs" "$SANDBOX/source.md")"
  assert_eq "$staged" "$SANDBOX/docs/dispatch/source.md"
  assert_file_has "$staged" "brief"
}
