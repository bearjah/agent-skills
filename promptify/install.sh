#!/usr/bin/env bash
# Symlink promptify into ~/.claude and register its trigger in CLAUDE.md.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
BEGIN='<!-- promptify:begin -->'
END='<!-- promptify:end -->'

mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/commands"

SKILL_LINK="$CLAUDE_DIR/skills/promptify"
CMD_LINK="$CLAUDE_DIR/commands/p.md"

# Refuse to nest inside (or clobber) a real, non-symlink path. `ln -sfn` only
# guards against replacing a symlink-to-dir; a genuine directory or file at
# these paths would otherwise silently absorb the new symlink underneath it.
if [ -e "$SKILL_LINK" ] && [ ! -L "$SKILL_LINK" ]; then
  echo "error: $SKILL_LINK already exists and is not a symlink. Remove or rename it, then re-run install.sh." >&2
  exit 1
fi
if [ -e "$CMD_LINK" ] && [ ! -L "$CMD_LINK" ]; then
  echo "error: an existing /p command was found at $CMD_LINK and will not be overwritten. Remove or rename it, then re-run install.sh." >&2
  exit 1
fi

ln -sfn "$HERE" "$SKILL_LINK"
ln -sfn "$HERE/commands/p.md" "$CMD_LINK"

# Resolve CLAUDE.md through any existing symlink so a dotfile-managed file
# (stow/chezmoi, etc.) is edited in place instead of being replaced by a
# plain file that would orphan the managed copy.
MD="$CLAUDE_DIR/CLAUDE.md"
if [ -e "$MD" ]; then
  MD="$(readlink -f "$MD")"
fi

# Back up any pre-existing, non-empty CLAUDE.md before mutating it.
BACKUP=""
if [ -s "$MD" ]; then
  BACKUP="$MD.bak"
  cp -p "$MD" "$BACKUP"
fi

touch "$MD"

# Drop any previous block so re-running never duplicates it. Marker lines
# must match the WHOLE line exactly (not merely appear as a substring), so a
# mention of the marker text inside ordinary prose is never mistaken for a
# real block boundary. If a begin marker has no matching end marker, the
# block is malformed (e.g. from a manual edit) — abort loudly rather than
# silently deleting everything from that line to EOF.
begin_count="$(grep -xcF "$BEGIN" "$MD" || true)"
if [ "$begin_count" -gt 0 ]; then
  end_count="$(grep -xcF "$END" "$MD" || true)"
  if [ "$begin_count" -ne "$end_count" ]; then
    echo "error: $MD has an unterminated promptify block ($begin_count begin marker(s), $end_count end marker(s) found). Fix it by hand, then re-run install.sh." >&2
    exit 1
  fi
  awk -v b="$BEGIN" -v e="$END" '
    $0 == b { skip = 1 }
    !skip   { print }
    $0 == e { skip = 0 }
  ' "$MD" > "$MD.tmp"
  # Write the stripped content back into the existing file (not `mv` over
  # it), so its mode/ownership and the CLAUDE.md-symlink resolution above
  # both survive the rewrite.
  cat "$MD.tmp" > "$MD"
  rm -f "$MD.tmp"
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
  "$SKILL_LINK" \
  "$CMD_LINK" \
  "$MD"
if [ -n "$BACKUP" ]; then
  printf '  %s (backup of previous CLAUDE.md)\n' "$BACKUP"
fi
