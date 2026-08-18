# Codex dispatch adapter

Installs the portable `promptify` and `finalize-work` skills into
`~/.codex/skills` and provides `~/.codex/scripts/dispatch-task.sh`.

The dispatcher creates isolated worktrees at
`~/.codex/worktrees/<repo>/<slug>` and starts an interactive Codex session in
a new tmux window. It accepts the same repository, brief, cleanup, base, and
reference arguments as the shared workflow, plus Codex's
`--approval-policy untrusted|on-request|never`.

Install it with:

```bash
./install.sh
```

Set `DISPATCH_WORKTREE_ROOT` to override the worktree root.
