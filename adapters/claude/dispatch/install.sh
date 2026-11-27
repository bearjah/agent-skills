#!/usr/bin/env bash
# Symlink the dispatch tool into ~/.claude.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
source "$REPO_ROOT/core/dispatch/lib/docs.sh"
DOCS_ROOT="$(agent_docs_root)"
mkdir -p "$HOME/.claude/scripts" "$HOME/.claude/commands" "$HOME/.claude/skills"
ensure_agent_docs_root "$DOCS_ROOT"

# Earlier versions linked finalize-work and git-commit skills that have since
# been removed. Clear a link only when it points at nothing, so a skill of the
# user's own under the same name is left alone.
for retired in finalize-work git-commit; do
  stale_link="$HOME/.claude/skills/$retired"
  if [ -L "$stale_link" ] && [ ! -e "$stale_link" ]; then
    rm -- "$stale_link"
  fi
done

ln -sfn "$HERE/bin/dispatch-task.sh" "$HOME/.claude/scripts/dispatch-task.sh"
ln -sfn "$HERE/commands/dispatch.md" "$HOME/.claude/commands/dispatch.md"

printf 'installed:\n  %s\n  %s\n' \
  "$HOME/.claude/scripts/dispatch-task.sh" \
  "$HOME/.claude/commands/dispatch.md"
