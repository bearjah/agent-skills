# Engineering workflow (agent-skills plugin)

The agent-skills plugin is installed (skills are namespaced `agent-skills:<name>`). Before starting coding work, check whether one of its skills applies and invoke it with the Skill tool instead of working from memory. Match the amount of process to the task:

- **Trivial** (typo, rename, one-line config, a question, non-coding work): just do it, no skill needed.
- **Bug or failure**: `debugging-and-error-recovery` → regression test via `test-driven-development` → `code-review-and-quality` before calling it done.
- **New feature or non-trivial change**: `spec-driven-development` (if requirements are unclear, `interview-me` first) → `planning-and-task-breakdown` → `incremental-implementation` with `test-driven-development` → `code-review-and-quality` (add `security-and-hardening` when it touches auth, user input, secrets or permissions) → `git-workflow-and-versioning` when committing.
- **Specialised work**: use the matching skill: UI → `frontend-ui-engineering`, APIs → `api-and-interface-design`, performance → `performance-optimization`, CI → `ci-cd-and-automation`, migrations → `deprecation-and-migration`, docs/ADRs → `documentation-and-adrs`, logging/metrics → `observability-and-instrumentation`, deploys → `shipping-and-launch`.

State in one line which skill you're applying so I can redirect. If I say "just do it" or "quick fix", skip the process.

# Model routing

Claude Code has no automatic model router, so route work yourself. The main session does the judgement work; push mechanical and high-volume work down to cheaper models:

| Work | Send to | Model |
|---|---|---|
| Find files/symbols/call sites; read and summarise code, logs, diffs, docs | `scout` agent | Haiku |
| Run tests, builds, linters, type-checks and summarise failures | `runner` agent | Haiku |
| Complex plans: multi-module or cross-service work, new architecture or data model, migrations, security/concurrency-sensitive changes, more than ~5 tasks, or real unknowns | `planner` agent | Fable 5.2 |
| Simple plans: one module, a few clear steps | main session | session model |
| Implement a task that is already specified (approved plan, clear acceptance criteria) | `implementer` agent | Sonnet |
| `agent-skills:test-engineer`, `agent-skills:web-performance-auditor`, `agent-skills:accessibility-auditor` | pass `model: "sonnet"` | Sonnet |
| Specs, plans, design trade-offs, root-causing hard bugs, final review, `agent-skills:code-reviewer`, `agent-skills:security-auditor` | main session / inherit | session model |

Rules:
- Before planning, state the call in one line (e.g. "Plan: complex → Fable planner") so I can override it. "Plan this with Fable" or "keep the plan simple" from me wins.
- Give the `planner` the full spec/requirements, constraints and decisions from this conversation, plus `scout` findings if you have them. Review its plan before presenting it to me for approval.
- Don't delegate anything that takes only a handful of tool calls. A subagent's start-up cost outweighs the saving.
- Briefs must stand alone (goal, files, acceptance criteria, what's ruled out), because the agent can't see this conversation.
- Run independent delegated tasks in parallel.
- If a cheaper agent's result looks wrong, incomplete or hit ambiguity, take that piece back to the main session instead of retrying on the same tier.
- Review what `implementer` produced before reporting it done.

# Working agreement: plan with me, then run alone

Non-trivial work has two phases. Trivial work (see above) skips this.

## Phase 1: planning, with me

We discuss the scope, then I approve three things, in order: (1) the scope and the Definition of Done, (2) the spec, (3) the implementation plan. For small work, offer them as one approval.

- The Definition of Done is a checklist where every item can be verified by a command or an observation: acceptance criteria, tests, CI green, review done, docs updated, and the end state (merged, deployed, or PR left open, and why).
- Ask every question you have now, each with a recommendation. This is the time to interrupt me.
- The spec and the plan are committed in the docs directory of the repo the work is delivered to: that repo's own convention if it has one, otherwise `docs/designs/YYYY-MM-DD-<slug>-spec.md` and `docs/plans/YYYY-MM-DD-<slug>-plan.md`. Commit them before the next code commit so they are in the task's pull request, name both paths in its description, and update them there when the work departs from them. Repo-relative paths only: no machine paths or private names.
- Before I approve the plan, list what execution will need from me (access, credentials, accounts, decisions you can foresee) so I can give it upfront.

## Phase 2: execution, alone

Once I approve the plan, work until the Definition of Done is met. Do not ask me to approve commits, pushes, pull requests, reviews or merges.

- Decide implementation details yourself and record each notable decision in the pull request description.
- Review your own pull request with `code-review-and-quality`, fix what it finds, and get CI green.
- Merge the pull request yourself when the Definition of Done is met, in any repo where you have permission to. Never get around branch protection or a required review: if the repo requires someone's approval, request it, notify me, and carry on with other work.
- If one part is blocked, keep going on the parts that are not.

Interrupt me only when:
- the work has to go outside the approved scope, or the Definition of Done cannot be met as written;
- you need access, credentials or a payment only I can give;
- an action is destructive or irreversible and not in the approved plan (deleting data, force-pushing a shared branch, changing production, spending money);
- you are stuck after several genuinely different attempts.

When you do interrupt: one message saying what is blocked, the options and your recommendation, plus a push notification.

## When it is ready

Check every Definition of Done item and keep the evidence. Then send a push notification and a short report: what was delivered, pull request links and their merge state, the checklist with evidence, the decisions you made, and anything left over.
