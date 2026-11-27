#!/usr/bin/env bash
# Set up ~/.claude on a machine: link the global instructions and the agents
# they route work to, and enable the plugin whose skills they call.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"
PLUGIN="agent-skills@addy-agent-skills"
MARKETPLACE="addy-agent-skills"
MARKETPLACE_URL="https://github.com/addyosmani/agent-skills.git"

command -v jq >/dev/null 2>&1 || {
  printf 'install: jq is required to update %s\n' "$SETTINGS" >&2
  exit 1
}

# source path -> destination path, one pair per line
links() {
  printf '%s\t%s\n' "$HERE/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"
  local agent
  for agent in "$HERE"/agents/*.md; do
    printf '%s\t%s\n' "$agent" "$CLAUDE_DIR/agents/$(basename "$agent")"
  done
}

# Everything is checked before anything changes, so a refused install leaves
# the machine exactly as it was. A link, or a plain copy with the same content,
# is safe to replace; anything else is someone's own work.
while IFS=$'\t' read -r source destination; do
  if [ -e "$destination" ] && [ ! -L "$destination" ] && ! cmp -s "$source" "$destination"; then
    printf 'install: %s exists and differs from %s; move it aside and re-run\n' \
      "$destination" "$source" >&2
    exit 1
  fi
done < <(links)

if [ -e "$SETTINGS" ] && ! jq -e 'type == "object"' "$SETTINGS" >/dev/null 2>&1; then
  printf 'install: %s is not a JSON object; fix it and re-run\n' "$SETTINGS" >&2
  exit 1
fi

mkdir -p "$CLAUDE_DIR/agents"
while IFS=$'\t' read -r source destination; do
  ln -sfn "$source" "$destination"
  printf 'linked: %s\n' "$destination"
done < <(links)

# Settings hold personal choices (model, theme, permission mode), so they are
# not linked. Only the two plugin entries are added; the rest is kept.
[ -e "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"
updated="$(mktemp "$SETTINGS.XXXXXX")"
jq --arg plugin "$PLUGIN" --arg market "$MARKETPLACE" --arg url "$MARKETPLACE_URL" '
  .enabledPlugins[$plugin] = true
  | .extraKnownMarketplaces[$market] = {source: {source: "git", url: $url}}
' "$SETTINGS" > "$updated"
mv "$updated" "$SETTINGS"
printf 'enabled plugin: %s in %s\n' "$PLUGIN" "$SETTINGS"
