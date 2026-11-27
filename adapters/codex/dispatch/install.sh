#!/usr/bin/env bash
# Install the Codex adapter without copying the portable skill sources.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
CODEX_DIR="$HOME/.codex"
source "$REPO_ROOT/core/dispatch/lib/docs.sh"
DOCS_ROOT="$(agent_docs_root)"

mkdir -p "$CODEX_DIR/skills" "$CODEX_DIR/scripts"
ensure_agent_docs_root "$DOCS_ROOT"

for skill in promptify; do
  link="$CODEX_DIR/skills/$skill"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    printf 'install: %s exists and is not a symlink; move it aside and re-run\n' "$link" >&2
    exit 1
  fi
done

for skill in promptify; do
  link="$CODEX_DIR/skills/$skill"
  ln -sfn "$REPO_ROOT/skills/$skill" "$link"
done

# Earlier versions linked finalize-work and git-commit skills that have since
# been removed. Clear a link only when it points at nothing, so a skill of the
# user's own under the same name is left alone.
for retired in finalize-work git-commit; do
  stale_link="$CODEX_DIR/skills/$retired"
  if [ -L "$stale_link" ] && [ ! -e "$stale_link" ]; then
    rm -- "$stale_link"
  fi
done

ln -sfn "$HERE/bin/dispatch-task.sh" "$CODEX_DIR/scripts/dispatch-task.sh"

printf 'installed:\n  %s\n  %s\n' \
  "$CODEX_DIR/skills/promptify" \
  "$CODEX_DIR/scripts/dispatch-task.sh"
