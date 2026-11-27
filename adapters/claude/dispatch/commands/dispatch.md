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

1. **Task and product intent** — the problem, intended outcomes, and product
   changes or proposals. Distinguish settled decisions from unresolved proposals.
2. **Repos** — a table of path, role (primary/target/reference), branch, and why
   each is in scope. `--add-dir` grants tool access but does **not** load a
   sibling's `CLAUDE.md`, so name any sibling `CLAUDE.md` that must be read.
3. **Context already gathered** — files, prior art, links.
4. **Scope and requirements** — the work included, explicit exclusions,
   constraints, and known functional and non-functional requirements. Include
   relevant behavior and quality expectations already discussed with the user.
5. **Deliverable** — the intended outcome and acceptance criteria. Specs and
   implementation plans are committed in the target repository's docs directory
   (`docs/designs/` and `docs/plans/` unless the repository has its own
   convention). Use absolute paths under `$docs_root/<canonical-repo>/reviews/`
   for reviews and `$docs_root/research/` for evidence.
   Implementation tasks finish with a validated PR, not just documents.
6. **Dispatch metadata** — base ref and date.
7. **Decisions and execution scope** — carry forward decisions already made,
   existing approval evidence, any open questions, and existing spec/plan paths
   if available. State whether this is implementation, planning, research, or
   review only, and any explicit later human approval gates.
8. **Known validation context** — existing checks, commands, runtimes, services,
   fixtures, access prerequisites, and evidence already gathered. The child
   defines the full validation approach during implementation planning.

The brief must carry all relevant information already established. Do not
require a spec, implementation plan, or completed design discussion before
launch: the new session develops those as needed. If clarification is needed,
the child discusses it with the user in that new session; otherwise it proceeds
from the brief without repeating settled questions.

Both adapters load the shared dispatch workflow from
`core/dispatch/workflow.md` in the installed agent-skills repository. The child
writes a spec when needed, writes the implementation plan with checks covering
the scope and functional and non-functional requirements, implements, executes
those checks in a working environment, and creates a PR autonomously. Questions
block dependent work until answered; independent work can continue. An independent
reviewer subagent must comprehensively review each stage before the next begins.
Findings are fixed and re-reviewed. Related work that must be deferred gets a real, verified
follow-up dispatch with a linked brief and explicit dependency base; required
acceptance work still blocks parent completion until it is done.

The spawned session runs with `--permission-mode auto` by default, since nobody
is watching it until you switch to its window. Pass `--permission-mode plan` for
read-only research.

Pick the entry skill by the stage actually needed: `superpowers:brainstorming`
for product or design clarification, `superpowers:systematic-debugging` for a bug,
or `superpowers:writing-plans` when a spec already exists. The default entry
skill does not require repeating discussions already captured in the brief.

Never place a durable brief, design, review, or research artifact in a target
repository's `docs/` directory.

Then run:

```!
~/.claude/scripts/dispatch-task.sh $ARGUMENTS
```
