#!/usr/bin/env bash
# Symlink the dispatch tool into ~/.claude.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$HOME/.claude/scripts" "$HOME/.claude/commands" "$HOME/docs/dispatch"

ln -sfn "$HERE/bin/dispatch-task.sh" "$HOME/.claude/scripts/dispatch-task.sh"
ln -sfn "$HERE/commands/dispatch.md" "$HOME/.claude/commands/dispatch.md"

printf 'installed:\n  %s\n  %s\n' \
  "$HOME/.claude/scripts/dispatch-task.sh" \
  "$HOME/.claude/commands/dispatch.md"
