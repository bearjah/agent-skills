---
description: "Dispatch an isolated session that autonomously completes agreed work through reviewed planning, implementation, validation, and PR creation"
argument-hint: "--slug SLUG --brief PATH --target REPO [--ref REPO] [--skill NAME] [--permission-mode MODE]"
allowed-tools: ["Bash(~/.claude/scripts/dispatch-task.sh:*)"]
---

# Dispatch Task

The new session opens as a tmux window or a herdr tab, whichever you are in.
The backend is detected from `$TMUX` / `$HERDR_ENV`, so there is nothing to
pass; the report's `switch:` line tells you how to reach it.

Resolve `docs_root=${AGENT_DOCS_ROOT:-$HOME/docs}`. Before running this, write
the briefing to `$docs_root/dispatch/YYYY-MM-DD-<slug>.md`
with these sections:

1. **Task** — the intent, in a few sentences.
2. **Repos** — a table of path, role (primary/target/reference), branch, and why
   each is in scope. `--add-dir` grants tool access but does **not** load a
   sibling's `CLAUDE.md`, so name any sibling `CLAUDE.md` that must be read.
3. **Context already gathered** — files, prior art, links.
4. **Constraints and non-goals.**
5. **Deliverable** — the intended outcome and acceptance criteria. Use absolute
   paths under `$docs_root/<canonical-repo>/designs/` for specs, `plans/` for
   implementation plans, `reviews/` for reviews, and `research/` for evidence.
   Implementation tasks finish with a validated PR, not just documents.
6. **Dispatch metadata** — base ref and date.
7. **Agreement and execution scope** — record the user's agreed brainstorming
   outcome and high-level plan, with approval evidence, existing spec/plan paths,
   and any decisions still open. State whether this is implementation, planning,
   research, or review only, and any explicit later human approval gates.
8. **Validation environment** — required commands, runtimes, services, fixtures,
   and known access prerequisites. Include evidence already gathered.

Both adapters load the shared dispatch workflow from
`core/dispatch/workflow.md` in the installed agent-skills repository. Once
brainstorming and the high-level plan are agreed, the child writes a spec when
needed, writes the implementation plan, implements, validates in a working
environment, and creates a PR autonomously. An independent reviewer subagent
must comprehensively review each stage before the next begins. Findings are
fixed and re-reviewed. Related work that must be deferred gets a real, verified
follow-up dispatch with a linked brief and explicit dependency base; required
acceptance work still blocks parent completion until it is done.

The spawned session runs with `--permission-mode auto` by default, since nobody
is watching it until you switch to its window. Pass `--permission-mode plan` for
read-only research.

Pick the entry skill by task kind: `superpowers:brainstorming` to build or change
behavior, `superpowers:systematic-debugging` for a bug, `superpowers:writing-plans`
when a spec already exists.

Never place a durable brief, design, review, or research artifact in a target
repository's `docs/` directory.

Then run:

```!
~/.claude/scripts/dispatch-task.sh $ARGUMENTS
```
