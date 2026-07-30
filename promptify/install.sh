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
  echo "error: $SKILL_LINK already exists and is not a symlink. Nothing was installed. Remove or rename it, then re-run install.sh." >&2
  exit 1
fi
if [ -e "$CMD_LINK" ] && [ ! -L "$CMD_LINK" ]; then
  echo "error: an existing /p command was found at $CMD_LINK and will not be overwritten. Nothing was installed. Remove or rename it, then re-run install.sh." >&2
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

# Back up a pre-existing, non-empty CLAUDE.md exactly once. Never clobber an
# existing backup: if a later re-run started from a bad file, overwriting a
# good backup with it would destroy the one safety net the user has. The
# first backup ever made is always the truest "before promptify" snapshot.
if [ -s "$MD" ] && [ ! -e "$MD.bak" ]; then
  cp -p "$MD" "$MD.bak"
fi

# Compose the whole new CLAUDE.md into a temp file and commit it with a
# single atomic rename at the very end. Nothing below this point ever opens
# $MD for writing, so a failure at any step -- expected (a malformed block)
# or not (a crash, ENOSPC, a permissions surprise) -- leaves $MD exactly as
# it was found.
TMP="$MD.tmp"
trap 'rm -f "$TMP"' EXIT

abort() {
  echo "error: $1" >&2
  echo "  skill symlink: installed at $SKILL_LINK" >&2
  echo "  command symlink: installed at $CMD_LINK" >&2
  if [ -e "$MD.bak" ]; then
    echo "  CLAUDE.md: left unmodified; a backup is available at $MD.bak" >&2
  else
    echo "  CLAUDE.md: left unmodified (no backup exists; the file was empty or did not previously exist)" >&2
  fi
  echo "  Fix $MD by hand, then re-run install.sh." >&2
  exit 1
}

# Seed the temp file with the original's content and mode (or start empty, if
# there is no original yet). `cp -p` captures the mode up front, but a
# read-only source (444, say) would make $TMP read-only too and block our
# OWN writes below -- so force it writable for the duration of composition,
# then restore the exact original mode right before the atomic commit. This
# also keeps the read-only case working at all: `mv` doesn't need write
# access to the file it replaces, only to its directory, so the commit
# succeeds even when $MD itself is read-only.
ORIG_MODE=""
if [ -e "$MD" ]; then
  ORIG_MODE="$(stat -c '%a' "$MD")"
  cp -p "$MD" "$TMP"
  chmod u+rw "$TMP"
else
  : > "$TMP"
fi

# Strip any previous block -- but only if the file holds exactly one
# well-formed BEGIN...END pair. Marker lines must match a WHOLE line exactly
# (never a substring), and the parse is ordering-aware: a lone begin with no
# end, an end with no preceding begin, or a duplicate of either aborts
# instead of silently deleting to EOF (or past a later, unrelated mention of
# the marker text in prose).
if [ -s "$MD" ]; then
  if ! awk -v b="$BEGIN" -v e="$END" '
    BEGIN { state = 0 }
    $0 == b {
      if (state != 0) { exit 1 }
      state = 1
      next
    }
    $0 == e {
      if (state != 1) { exit 1 }
      state = 2
      next
    }
    state != 1 { print }
    END {
      if (state == 1) { exit 1 }
    }
  ' "$MD" > "$TMP"; then
    abort "$MD has a malformed promptify block (missing, duplicated, or out-of-order markers)."
  fi
fi

# Guarantee a newline before appending, so the block never glues onto prior text.
if [ -s "$TMP" ] && [ "$(tail -c1 "$TMP" | wc -l)" -eq 0 ]; then
  printf '\n' >> "$TMP"
fi

cat >> "$TMP" <<EOF
$BEGIN
# promptify
- **promptify** (\`~/.claude/skills/promptify/SKILL.md\`) - optimize a raw prompt, then run it on approval. Trigger: \`/promptify\` or \`/p\`
When the user types \`/promptify\` or \`/p\`, invoke the Skill tool with \`skill: "promptify"\` before doing anything else.
$END
EOF

if [ -n "$ORIG_MODE" ]; then
  chmod "$ORIG_MODE" "$TMP"
fi

mv "$TMP" "$MD"
trap - EXIT

printf 'installed:\n  %s\n  %s\n  %s (trigger block)\n' \
  "$SKILL_LINK" \
  "$CMD_LINK" \
  "$MD"
if [ -e "$MD.bak" ]; then
  printf '  %s (backup of pre-install CLAUDE.md)\n' "$MD.bak"
fi
