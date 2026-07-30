# claude-dispatch

Spawns a new window running an independent, pre-briefed session in an isolated
git worktree. Works under either **tmux** or **herdr**.

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

## Multiplexers

The window goes wherever you are. The backend is detected, not configured:

| Detected | Backend | New session appears as |
|---|---|---|
| `$TMUX` set | tmux | a window via `tmux new-window` |
| `$HERDR_ENV=1` | herdr | a tab via `herdr tab create` + `herdr pane run` |
| neither | — | hard fail before any worktree is created |

`$TMUX` wins when both are set: herdr exports `HERDR_ENV` into every process it
starts, so a tmux session inside a herdr tab still carries it, and the innermost
multiplexer owns the window you are looking at. Override with
`DISPATCH_MUX=tmux|herdr`.

The report's `switch:` line is written in the terms of whichever backend ran —
`tmux select-window` or `herdr tab focus`.

Two things differ under herdr, both handled:

- **herdr cannot open a tab running a command.** `tab create` takes a cwd and a
  label but no argv, so the pane comes up at a shell prompt and the command is
  sent afterwards with `pane run`.
- **`pane run` evaluates, it does not exec.** It joins its arguments and hands
  the result to the pane's shell, so everything is `printf %q`-quoted first.
  Without that the prompt would arrive as one argument per word, and a `$(...)`
  in a brief path would run. The herdr test double evals the same way the real
  client does, so the quoting is pinned by the suite rather than assumed.

The herdr backend reads a pane id out of herdr's JSON reply, so it needs
`python3` — checked in preflight, not at the point of failure.

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
against a private tmux server, and the herdr cases run against a stub client,
so neither suite touches your live session. `HERDR_ENV` is pinned rather than
inherited for the same reason: a suite run from inside a herdr tab must not
open tabs in the session you are sitting in.
