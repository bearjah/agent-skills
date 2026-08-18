#!/usr/bin/env bash
# Symlink the dispatch tool into ~/.claude.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
source "$REPO_ROOT/core/dispatch/lib/docs.sh"
DOCS_ROOT="$(agent_docs_root)"
mkdir -p "$HOME/.claude/scripts" "$HOME/.claude/commands" "$HOME/.claude/skills" \
  "$HOME/.claude/worktrees"
ensure_agent_docs_root "$DOCS_ROOT"

SKILL_LINK="$HOME/.claude/skills/finalize-work"

# Checked before anything is linked, so a rejected install leaves nothing behind.
# Only the skill path needs this: `ln -sfn` replaces a file or a symlink, but at
# a real directory it creates the link *inside* it, which would leave the skill
# silently undiscoverable at ~/.claude/skills/finalize-work/finalize-work.
if [ -e "$SKILL_LINK" ] && [ ! -L "$SKILL_LINK" ]; then
  printf 'install: %s exists and is not a symlink; move it aside and re-run\n' \
    "$SKILL_LINK" >&2
  exit 1
fi

ln -sfn "$HERE/bin/dispatch-task.sh" "$HOME/.claude/scripts/dispatch-task.sh"
ln -sfn "$HERE/commands/dispatch.md" "$HOME/.claude/commands/dispatch.md"
ln -sfn "$REPO_ROOT/skills/finalize-work" "$SKILL_LINK"

printf 'installed:\n  %s\n  %s\n  %s\n' \
  "$HOME/.claude/scripts/dispatch-task.sh" \
  "$HOME/.claude/commands/dispatch.md" \
  "$SKILL_LINK"
