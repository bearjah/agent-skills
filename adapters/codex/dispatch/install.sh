#!/usr/bin/env bash
# Install the Codex adapter without copying the portable skill sources.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
CODEX_DIR="$HOME/.codex"

mkdir -p "$CODEX_DIR/skills" "$CODEX_DIR/scripts" "$CODEX_DIR/worktrees" "$HOME/docs/dispatch"

for skill in promptify finalize-work; do
  link="$CODEX_DIR/skills/$skill"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    printf 'install: %s exists and is not a symlink; move it aside and re-run\n' "$link" >&2
    exit 1
  fi
  ln -sfn "$REPO_ROOT/skills/$skill" "$link"
done

ln -sfn "$HERE/bin/dispatch-task.sh" "$CODEX_DIR/scripts/dispatch-task.sh"

printf 'installed:\n  %s\n  %s\n  %s\n' \
  "$CODEX_DIR/skills/promptify" \
  "$CODEX_DIR/skills/finalize-work" \
  "$CODEX_DIR/scripts/dispatch-task.sh"
