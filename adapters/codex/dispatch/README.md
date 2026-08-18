# Codex dispatch adapter

Installs `~/.codex/scripts/dispatch-task.sh` and the portable `promptify` and
`finalize-work` skills:

```bash
./install.sh
```

Dispatch creates an isolated worktree under `~/.codex/worktrees`, then opens
Codex in the current terminal environment: tmux when `$TMUX` is set, otherwise
Herdr when `$HERDR_ENV=1`. Use `DISPATCH_MUX=tmux|herdr` to override detection
and `DISPATCH_WORKTREE_ROOT` to override the worktree root. Durable documents
go under `${AGENT_DOCS_ROOT:-$HOME/docs}` and that directory is automatically
made writable in the spawned session. Sessions start with high reasoning and
Vim composer mode. Permission settings inherit the user's Codex configuration.
Override them per session with
`--sandbox workspace-write --approval-policy on-request`, or set
`DISPATCH_CODEX_SANDBOX` and
`DISPATCH_CODEX_APPROVAL_POLICY`.

```bash
dispatch-task.sh --slug TASK --brief BRIEF.md --target REPO
```
