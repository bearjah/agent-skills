---
description: "Dispatch a briefed session into an isolated worktree in a new tmux window"
argument-hint: "--slug SLUG --brief PATH --target REPO [--ref REPO] [--skill NAME] [--permission-mode MODE]"
allowed-tools: ["Bash(~/.claude/scripts/dispatch-task.sh:*)"]
---

# Dispatch Task

Before running this, write the briefing to `~/docs/dispatch/YYYY-MM-DD-<slug>.md`
with these sections:

1. **Task** — the intent, in a few sentences.
2. **Repos** — a table of path, role (primary/target/reference), branch, and why
   each is in scope. `--add-dir` grants tool access but does **not** load a
   sibling's `CLAUDE.md`, so name any sibling `CLAUDE.md` that must be read.
3. **Context already gathered** — files, prior art, links.
4. **Constraints and non-goals.**
5. **Deliverable** — the spec path, `~/docs/designs/YYYY-MM-DD-<slug>-design.md`.
6. **Dispatch metadata** — base ref and date.

The spawned session runs with `--permission-mode auto` by default, since nobody
is watching it until you switch to its window. Pass `--permission-mode plan` for
read-only research.

Pick the entry skill by task kind: `superpowers:brainstorming` to build or change
behavior, `superpowers:systematic-debugging` for a bug, `superpowers:writing-plans`
when a spec already exists.

Then run:

```!
~/.claude/scripts/dispatch-task.sh $ARGUMENTS
```
