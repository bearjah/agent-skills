# promptify

Rewrites a raw prompt using prompt-engineering best practices, shows the
rewrite, and runs it on approval.

## Install

```bash
./install.sh
```

Symlinks `~/.claude/skills/promptify` and `~/.claude/commands/p.md` into this
repo, and regenerates a trigger block in `~/.claude/CLAUDE.md`. Safe to re-run
after a `git pull` — but read "What the installer touches" below before you
rely on that, especially if you've hand-edited the generated block or manage
`CLAUDE.md` through a dotfiles tool.

## Use

```
/p make the dashboard faster       short form
/promptify <raw prompt>            explicit form
/p                                 optimize my previous message
```

It classifies the prompt, runs bounded recon whenever resolving a real path
would change what the rewrite says — regardless of prompt kind, and skipped
when the deliverable doesn't turn on any specific file — asks up to three
questions where a wrong guess would fork the work, rewrites, and then waits
for `go` / `edit <note>` / `cancel`.

Already-precise and trivial prompts bypass the pipeline and run as-is.

## Layout

| Path | Role |
|---|---|
| `SKILL.md` | Pipeline, universal rules, output contract — always loaded |
| `references/lenses.md` | Per-domain rules — read only for the detected kind |
| `references/examples.md` | Four regression cases, run by hand |
| `commands/p.md` | Thin `/p` delegator |
| `install.sh` | Symlinks skill + command, registers the trigger block in `CLAUDE.md` |
| `test/` | Test suite (`helpers.sh`, `run-tests.sh`, `test_structure.sh`, `test_install.sh`) |
| `DESIGN.md` | The approved spec |
| `PLAN.md` | The implementation plan |
| `README.md` | This file |

## What the installer touches

`install.sh` finds the block delimited by `<!-- promptify:begin -->` /
`<!-- promptify:end -->` in `~/.claude/CLAUDE.md`, deletes it, and appends a
freshly generated one — everything outside the block is left untouched. Three
consequences follow directly from that design:

- **Manual edits inside the block don't survive a re-run.** The block is
  regenerated from scratch every time, so anything you hand-edit inside the
  markers is silently discarded on the next install. Put customizations
  outside the markers.
- **The file is replaced via an atomic rename (`mv`), not an in-place write**,
  so `CLAUDE.md` gets a new inode on every install. If you've hard-linked
  `~/.claude/CLAUDE.md` into a dotfiles repo, that hard link is broken by an
  install — the dotfiles copy stops tracking the live file. A symlink at
  `~/.claude/CLAUDE.md` is fine: it's resolved and written through, so
  symlink-based dotfile management (GNU Stow, for instance) keeps working —
  a manager whose default mode copies rendered files rather than symlinking
  them (chezmoi's `apply`, for instance) doesn't get this protection, since
  there's no symlink there to resolve through. The atomic rename is a
  deliberate trade: it guarantees a crash or a disk-full
  error can never leave `CLAUDE.md` truncated or half-written, at the cost of
  hard-link preservation.
- **A backup is written to `CLAUDE.md.bak`**, but only on the first install
  that finds an existing, non-empty `CLAUDE.md`, and it is never overwritten
  by later runs. That first backup is your recovery path back to whatever was
  there before promptify.

The installer also refuses to change anything, and aborts before touching a
single file, if it finds:

- a malformed promptify block in `CLAUDE.md` (an unterminated `begin`, an
  `end` with no matching `begin`, or either marker duplicated), or
- a real file or directory (not a symlink) already sitting at
  `~/.claude/skills/promptify` or `~/.claude/commands/p.md`.

In every abort case, `CLAUDE.md` is left exactly as it was found.

## Test

```bash
./test/run-tests.sh
```

32 tests (14 structure + 18 install). Covers frontmatter, required sections,
line budgets, symlinks, and the installer's idempotency and guard behavior.
Prose quality is checked by hand against `references/examples.md`.
