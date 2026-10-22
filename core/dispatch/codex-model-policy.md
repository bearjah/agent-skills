# Codex dispatch model policy

This policy applies to the Codex adapter. It supplements the shared dispatch
workflow without changing scope, permission limits, or review gates. Model and
reasoning choices are explicit; do not inherit an unrelated configured default.

| Responsibility | Model | Reasoning effort |
| --- | --- | --- |
| Lead: scope, coordination, ambiguity, integration, and acceptance | `gpt-6.1-sol` | `high` |
| Design, architecture, specification, and implementation planning | `gpt-6.1-sol` | `high` |
| File discovery, fact extraction, and evidence collection | `gpt-6-luna` | `high` |
| Small coding tasks with explicit interfaces and acceptance checks | `gpt-6-luna` | `high` |
| Cross-module changes, migrations, and difficult debugging | `gpt-6.1-sol` | `high` |
| Running prescribed checks and collecting their results | `gpt-6-luna` | `high` |
| Independent spec, plan, implementation, and validation reviews | `gpt-6.1-sol` | `high` |
| PR descriptions, task records, and follow-up brief drafts | `gpt-6-luna` | `high` |
| Exceptionally difficult architecture or unresolved review disputes | `gpt-6-astra` | `high` |

## Delegation and escalation

Keep the lead on Sol. Delegate bounded work to Luna with the relevant source
context, explicit file ownership, interfaces, acceptance checks, and limits.
Use explicit model and reasoning parameters when spawning agents. Where model
overrides require a fresh agent, use `fork_turns="none"` and supply that context
in the task message. Do not assume a full-history fork changed models.

Every worker inherits the shared workflow's modularity, maintainability, and
completion requirements. A smaller model's assignment must still include the
relevant module interfaces, failure paths, and validation checks. Escalate when
those requirements cannot be met within the assignment; do not trade them away
for lower cost or leave required cleanup for later.

Escalate Luna work to Sol when it requires an unspecified design decision,
crosses its assigned boundaries, or remains unresolved after one correction
cycle. Luna must report the issue and return control before expanding scope.
Use Astra only for the exceptional cases in the table after Sol has identified
the difficulty; it is not the default reviewer or lead. Model escalation does
not authorize a new product decision or broader access.

Luna may execute checks and collect output. Sol decides whether the evidence
satisfies acceptance criteria. Independent review remains independent: an agent
must not review its own authored stage, including after a model escalation.
Sol reviews Luna's PR descriptions, task record updates, and child brief drafts
before using them for publication, progression, or follow-up dispatch.

If a model or model-selection control is unavailable, record that limitation and
keep bounded work on Sol when available. Never silently use a different model
or claim a Luna delegation occurred. If the required independent review cannot
be performed, follow the shared workflow's blocker procedure.

## Evidence and follow-ups

Record each agent's role, requested model, actual model and reasoning reported
by the runtime when available, and each escalation with its reason in the task
record. Distinguish requested settings from verified runtime metadata; mark
unavailable metadata as unverified. Link these entries to validation and review
results so cost savings can later be assessed against rework. Do not invent
usage, costs, or model verification.

Use the Codex dispatch adapter for Codex follow-ups so the lead starts on
`gpt-6.1-sol` with `high` reasoning and reads this policy again. Preserve the
parent's sandbox and approval limits as required by the shared workflow.
