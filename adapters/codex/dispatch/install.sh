#!/usr/bin/env bash
# Install the Codex adapter without copying the portable skill sources.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
CODEX_DIR="$HOME/.codex"
source "$REPO_ROOT/core/dispatch/lib/docs.sh"
DOCS_ROOT="$(agent_docs_root)"

mkdir -p "$CODEX_DIR/skills" "$CODEX_DIR/scripts" "$CODEX_DIR/worktrees"
ensure_agent_docs_root "$DOCS_ROOT"

for skill in promptify finalize-work git-commit; do
  link="$CODEX_DIR/skills/$skill"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    printf 'install: %s exists and is not a symlink; move it aside and re-run\n' "$link" >&2
    exit 1
  fi
done

for skill in promptify finalize-work git-commit; do
  link="$CODEX_DIR/skills/$skill"
  ln -sfn "$REPO_ROOT/skills/$skill" "$link"
done

ln -sfn "$HERE/bin/dispatch-task.sh" "$CODEX_DIR/scripts/dispatch-task.sh"

printf 'installed:\n  %s\n  %s\n  %s\n  %s\n' \
  "$CODEX_DIR/skills/promptify" \
  "$CODEX_DIR/skills/finalize-work" \
  "$CODEX_DIR/skills/git-commit" \
  "$CODEX_DIR/scripts/dispatch-task.sh"
