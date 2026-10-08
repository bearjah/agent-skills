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

Both adapters load the [shared execution workflow](../../../core/dispatch/workflow.md).
Record the agreed brainstorming outcome, high-level plan, acceptance criteria,
approval evidence, and validation prerequisites in the brief. Once agreement
exists, implementation sessions autonomously write a spec when needed, write an
implementation plan, implement, validate, and create a PR. Each stage requires
an independent reviewer subagent's review and resolution of its findings before
the next begins. A selected entry skill applies only to the relevant stage.

Validation must run successfully in a supported environment. Necessary setup is
part of the task; unavailable access is a blocker, not a passed check. Work that
must be split into a follow-up gets an actual verified dispatch with an explicit
dependency base and a linked record. Follow-ups needed for acceptance must finish
before the parent is ready. Planning/research/review-only briefs retain that
scope, and explicit human approval gates and permission limits remain in force.

Specs and plans live under `$AGENT_DOCS_ROOT/<canonical-repo>/designs/` and
`plans/` respectively (docs root defaults to `~/docs`). Reviews and validation
evidence live under the same repository's `reviews/`; briefs remain in
`$AGENT_DOCS_ROOT/dispatch/`. Shared docs are not committed without an explicit
request. PR creation does not authorize merging or deploying.
