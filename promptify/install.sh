#!/usr/bin/env bash
# Symlink promptify into ~/.claude and register its trigger in CLAUDE.md.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
MD="$CLAUDE_DIR/CLAUDE.md"
BEGIN='<!-- promptify:begin -->'
END='<!-- promptify:end -->'

mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/commands"

ln -sfn "$HERE" "$CLAUDE_DIR/skills/promptify"
ln -sfn "$HERE/commands/p.md" "$CLAUDE_DIR/commands/p.md"

touch "$MD"

# Drop any previous block so re-running never duplicates it.
if grep -qF "$BEGIN" "$MD"; then
  awk -v b="$BEGIN" -v e="$END" '
    index($0, b) { skip = 1 }
    !skip        { print }
    index($0, e) { skip = 0 }
  ' "$MD" > "$MD.tmp"
  mv "$MD.tmp" "$MD"
fi

# Guarantee a newline before appending, so the block never glues onto prior text.
if [ -s "$MD" ] && [ "$(tail -c1 "$MD" | wc -l)" -eq 0 ]; then
  printf '\n' >> "$MD"
fi

cat >> "$MD" <<EOF
$BEGIN
# promptify
- **promptify** (\`~/.claude/skills/promptify/SKILL.md\`) - optimize a raw prompt, then run it on approval. Trigger: \`/promptify\` or \`/p\`
When the user types \`/promptify\` or \`/p\`, invoke the Skill tool with \`skill: "promptify"\` before doing anything else.
$END
EOF

printf 'installed:\n  %s\n  %s\n  %s (trigger block)\n' \
  "$CLAUDE_DIR/skills/promptify" \
  "$CLAUDE_DIR/commands/p.md" \
  "$MD"
