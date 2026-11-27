#!/usr/bin/env bash
# Symlink the dispatch tool into ~/.claude.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
source "$REPO_ROOT/core/dispatch/lib/docs.sh"
DOCS_ROOT="$(agent_docs_root)"
mkdir -p "$HOME/.claude/scripts" "$HOME/.claude/commands" "$HOME/.claude/skills"
ensure_agent_docs_root "$DOCS_ROOT"

# Checked before anything is linked, so a rejected install leaves nothing behind.
# Only skill paths need this: `ln -sfn` replaces a file or a symlink, but at
# a real directory it creates the link *inside* it, which would leave the skill
# silently undiscoverable.
for skill in git-commit; do
  skill_link="$HOME/.claude/skills/$skill"
  if [ -e "$skill_link" ] && [ ! -L "$skill_link" ]; then
    printf 'install: %s exists and is not a symlink; move it aside and re-run\n' \
      "$skill_link" >&2
    exit 1
  fi
done

# Earlier versions linked a finalize-work skill that has since been removed.
# Clear the link only when it points at nothing, so a skill of the user's own
# under that name is left alone.
stale_link="$HOME/.claude/skills/finalize-work"
if [ -L "$stale_link" ] && [ ! -e "$stale_link" ]; then
  rm -- "$stale_link"
fi

ln -sfn "$HERE/bin/dispatch-task.sh" "$HOME/.claude/scripts/dispatch-task.sh"
ln -sfn "$HERE/commands/dispatch.md" "$HOME/.claude/commands/dispatch.md"
for skill in git-commit; do
  ln -sfn "$REPO_ROOT/skills/$skill" "$HOME/.claude/skills/$skill"
done

printf 'installed:\n  %s\n  %s\n  %s\n' \
  "$HOME/.claude/scripts/dispatch-task.sh" \
  "$HOME/.claude/commands/dispatch.md" \
  "$HOME/.claude/skills/git-commit"
