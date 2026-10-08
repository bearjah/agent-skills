# Dispatched task execution

Read the briefing and applicable repository instructions before acting. This
workflow applies to implementation tasks; a research-only, review-only, or
planning-only request ends at its requested deliverable. Permission modes and
explicit user limits still apply. Do not change permission settings to advance.

## Agreement and autonomy

Finish brainstorming and obtain the user's agreement on the design, high-level
plan, scope, and acceptance criteria before autonomous execution. Reuse approval
already recorded in the brief or session; do not repeat brainstorming or ask for
the same approval again. A launch, a suggested plan, or silence is not approval.
If agreement is missing, gather context and ask for the missing decision.

Once agreement is established for an implementation task, continue autonomously
through spec (when needed), implementation plan, implementation, validation, and
PR creation. Treat this dispatch workflow as delegation of subsequent technical
review gates to independent reviewer subagents within the agreed scope. Keep
design agreement, spec review, plan review, and implementation as separate gates.
Do not stop to offer execution choices or request routine permission to proceed.
An explicit user requirement to approve a later artifact still takes precedence;
planning skills' default approval pauses do not require duplicate approval after
the user has delegated these gates. Ask only for a material scope/design change,
missing authority, or a blocker that cannot be resolved with available access.

Use the selected entry skill only for its relevant stage. An already approved
design does not need fresh brainstorming just because it is the default skill.
Use `spec-plan` when available for specs and plans, or the available equivalent;
apply the delegated review gates above. Do not invoke a finalization workflow
that ends execution before the required PR has been created.

## Workspace and durable evidence

Inspect branches, worktrees, and status for every target. Continue in the
dispatched task worktrees; preserve unrelated changes and reference repositories.
Resolve canonical repository names from the source repositories in the brief,
not from task branch names or worktree directories.

Under the configured docs root, store specs in `<repo>/designs/`, implementation
plans in `<repo>/plans/`, reviews and validation evidence in `<repo>/reviews/`,
and briefs in `dispatch/`. Reuse matching existing artifacts. Do not commit the
shared docs repository unless explicitly requested. Maintain a task record with
approval evidence, artifact paths, stage status, review findings and resolutions,
validation results, follow-up dispatch identifiers, and PR URLs. Preserve this
record across session continuation rather than repeating completed stages.

## Review each stage before proceeding

After **each** spec, implementation plan, implementation, and validation stage,
spawn an independent reviewer subagent and wait for its comprehensive review.
The reviewer must not be the agent that authored the stage. Give it the original
request, agreed scope and acceptance criteria, repository instructions, relevant
artifacts/diff, and actual validation evidence. Ask it to inspect the underlying
files and assumptions, not just the author's summary. Reviewer access is for
review; the parent resolves findings and owns stage progression.

Require a verdict of PASS or CHANGES REQUIRED, with concrete findings, severity,
file/evidence references, and required corrections. Record the review and resolve
every actionable finding, then have the reviewer re-review the revised stage
before advancing. Unsupported findings may be dismissed with evidence, subject
to reviewer confirmation. Real work that must be split follows the follow-up
procedure below; a follow-up never substitutes for required acceptance criteria.
If a correction changes an earlier approved artifact, rerun the affected gates.
If reviewer tools are unavailable, record a blocker; self-review is not a
substitute. If review cycles stop making progress, report the concrete unresolved
decision rather than looping indefinitely or silently waiving the gate.

1. **Spec, if needed.** Reuse an adequate approved spec. Otherwise write one when
   behavior, interfaces, architecture, migration, or non-trivial risks need a
   durable contract. Cover goals, non-goals, acceptance criteria, failure paths,
   compatibility, and validation strategy. The reviewer checks completeness,
   consistency with the agreement, feasibility, and unresolved decisions. For a
   small change that needs no spec, record the rationale and have the plan
   reviewer confirm it; never invent a spec approval.
2. **Implementation plan.** Write concrete ordered tasks, affected files and
   interfaces, dependencies, acceptance checks, and exact validation commands.
   Inspect the actual environment now: required toolchains, services, fixtures,
   credentials/access, and CI or supported remote runners. Include necessary
   setup and environment fixes in the plan. The reviewer checks spec coverage,
   sequencing, scope, feasibility, and whether validation can actually run.
3. **Implementation.** Complete the agreed work and appropriate tests in the
   task worktrees. The reviewer inspects the complete diff for correctness,
   regressions, security, maintainability, edge cases, and test coverage against
   the spec and plan. Fix findings before the final validation stage.
4. **Validation.** Run the relevant checks and exercise the changed behavior in
   the available supported environment. Fix missing dependencies, configuration,
   fixtures, and services within existing authorization; use an authorized CI or
   remote runner when the local host cannot support a required check. Record
   exact commands, environment, exit status, results, and the tested revision or
   diff. A command that was skipped, failed to start, or needs inaccessible
   infrastructure is not a pass. Do not weaken checks to get a green result. The
   reviewer checks reproducibility, acceptance coverage, actual results, and any
   remaining gaps. If required validation cannot run, remain blocked and explain
   the missing prerequisite; do not claim completion or open a ready PR.
5. **PR.** After all applicable gates pass, commit the task changes, push the task
   branch, and create a PR (one per changed repository when necessary) against
   the intended base. Check for an existing PR first and update it instead of
   duplicating it. Include the behavior change, validation evidence, and linked
   follow-ups/dependencies; do not rely on private local document paths as the
   only reviewer context. Check required CI results on the pushed revision and
   resolve failures. Any code changes invalidate affected review and validation
   gates; rerun them before reporting readiness. Verify the PR URL, head, base,
   and status. Do not merge, deploy, or clean up worktrees unless separately
   authorized. If push/PR access or CI is blocked, record the exact failure and
   remaining step rather than claiming the task is done.

## Deferred work must start a follow-up session

Resolve discovered work needed for the agreed acceptance criteria in the current
task whenever possible. Do not leave TODOs, skipped validation, reviewer findings,
or "out of scope" labels as substitutes for completing agreed work.

When a concrete related item must be separated, write a child brief and actually
dispatch another top-level session using this adapter's dispatch script. This
workflow authorizes follow-ups needed for the agreed task, not unrelated features
or unbounded discovery. A materially new product decision still needs agreement.

- Give each distinct item a stable identifier and unique slug. Check the parent
  task record, existing child briefs, sessions, branches, and PRs first; reuse an
  existing follow-up instead of launching duplicates on review or resume.
- Include the parent brief/PR, exact scope and acceptance criteria, approval
  evidence (or decisions still needing approval), repository paths, dependency
  refs, validation environment, and this same review workflow in the child brief.
  Child sessions inherit only the approved scope, not permission to widen it.
- Preserve the parent's effective permission settings in the brief and launch:
  pass the same or stricter Claude permission mode, or Codex sandbox and approval
  policy. The launch prompt records explicit overrides; when it says settings
  were inherited, inspect the active configuration before choosing child flags.
  Never silently fall back to a more permissive adapter default. If the effective
  limits cannot be established, block the handoff rather than guessing.
- Use explicit target paths, a stable worktree root, and an explicit base ref.
  Never assume the dispatcher's default base contains the parent's changes.
  Commit a required parent dependency first and record its commit; if the child
  depends on unpublished/uncommitted work, resolve that dependency before launch.
  Never copy unrelated dirty changes or let children mutate the parent's worktree.
  Distinguish the worktree base commit from the PR target branch. Record both;
  dependent work may need a stacked PR against the parent's pushed branch and
  later retargeting after merge. For multiple repositories with different base
  refs, launch separate children because `--base` is shared across all targets.
- Record the dispatch command/result, child worktree and branch, session/window
  locator, and brief path. Verify the child process/session actually started;
  creating a brief or worktree alone is not dispatch success. If launch fails,
  inspect partial state before retrying and record the blocked handoff. Do not
  report the item as handled until launch has been verified.
- Keep ownership in the parent record. If the child is necessary for parent
  acceptance, wait for its result, integrate the dependency as appropriate, and
  repeat affected reviews and validation before declaring the parent ready.
  Independent follow-ups may continue separately, but report their actual state
  and links; launched does not mean completed. Do not recursively redispatch an
  unchanged blocked item or spawn speculative follow-ups. Continue non-blocked
  work, and surface the precise blocker when no authorized progress remains.

End with the PR URL(s), validation outcome, review verdicts, and the verified state
of every follow-up or blocker. A plan, a local commit, or a list of deferred work
alone does not complete an implementation dispatch.
