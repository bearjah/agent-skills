# Codex dispatch adapter

Installs `~/.codex/scripts/dispatch-task.sh` and the portable `promptify` and
`finalize-work` skills:

```bash
./install.sh
```

Dispatch creates an isolated worktree under
`$PWD/.codex/worktrees/<repo>/<slug>`, where `$PWD` is the directory from which
`dispatch-task.sh` was invoked, then opens Codex in the current terminal
environment: tmux when `$TMUX` is set, otherwise Herdr when `$HERDR_ENV=1`. Run
cleanup from that same directory, or set `DISPATCH_WORKTREE_ROOT` explicitly
for both commands. Use `DISPATCH_MUX=tmux|herdr` to override detection. Durable
documents go under `${AGENT_DOCS_ROOT:-$HOME/docs}` and that directory is
automatically made writable in the spawned session. Sessions start with high
reasoning and Vim composer mode. Permission settings inherit the user's Codex
configuration. Override them per session with
`--sandbox workspace-write --approval-policy on-request`, or set
`DISPATCH_CODEX_SANDBOX` and
`DISPATCH_CODEX_APPROVAL_POLICY`.

```bash
dispatch-task.sh --slug TASK --brief BRIEF.md --target REPO
```
