# claude-dispatch

Spawns a new tmux window running an independent, pre-briefed session in an
isolated git worktree.

A dispatch is a **separate top-level session, not a subagent**. There is no
shared context and no return value. Everything it knows comes from the brief;
everything you learn back comes from the artifact it writes.

## Install

```bash
./install.sh
```

Symlinks `bin/dispatch-task.sh` and `commands/dispatch.md` into `~/.claude/`,
making `/dispatch` available in sessions.

## Usage

Single repo:

```bash
dispatch-task.sh --slug fix-auth \
  --brief ~/docs/dispatch/2026-07-27-fix-auth.md \
  --target minimos
```

Cross-repo — the change lands in `minimos`, `minictl` is read for reference:

```bash
dispatch-task.sh --slug actions-contract \
  --brief ~/docs/dispatch/2026-07-27-actions-contract.md \
  --target minimos --ref minictl --ref actions
```

| Flag | Meaning |
|---|---|
| `--target` | The task may write to it. Gets a worktree on `dispatch/<slug>`. The first one is primary and becomes the session's cwd. |
| `--ref` | Read-only. Passed via `--add-dir` as its existing checkout. |
| `--base` | Base ref for worktrees. Default: auto-detected per repo. |
| `--skill` | Entry skill. Default `superpowers:brainstorming`. |
| `--permission-mode` | Permission mode for the spawned session. Default `auto`, so it does not sit blocked on a prompt before you switch to it. `plan` for read-only research; `""` defers to your settings. |

## Picking the primary

The primary is the repo **where the commit lands** — not where the answer
lives. If the change is in `minimos` but the workflow logic is in `minictl`,
the primary is still `minimos`. When a change spans repos, the primary is the
one the others follow.

## The constraint that shapes the brief

`--add-dir` grants **tool access, not context**. A sibling repo's `CLAUDE.md`
is *not* loaded — only the cwd's is. So the brief must name each sibling and
say what it is for, e.g. *"the workflow logic lives in
`~/code/minimusio/minictl`; read its `CLAUDE.md` first."* No flag closes this
gap.

## Cleanup

```bash
dispatch-task.sh --cleanup fix-auth --target minimos
```

Refuses a worktree with uncommitted changes or unmerged commits unless
`--force`.

## Tests

```bash
./test/run-tests.sh                    # unit and integration suite
./test/acceptance/run-acceptance.sh    # the acceptance gate
```

Both use a stub binary that records its argv, pinning the requirement that the
prompt precede the variadic `--add-dir`. Every case that needs tmux runs
against a private tmux server, so neither suite touches your live session.
