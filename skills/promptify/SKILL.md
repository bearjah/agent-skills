---
name: promptify
description: "Rewrite a raw prompt using prompt-engineering best practices, show the result, then run it on approval. Use when the user types /promptify or /p, or asks to optimize, sharpen, tighten, or improve a prompt before running it."
trigger: /promptify
---

# /promptify

Take the user's raw prompt, rewrite it into a well-specified one, show the
rewrite, and run it once they approve.

## Usage

```
/promptify <raw prompt>    rewrite, show, run on approval
/p <raw prompt>            same thing, short form
/promptify                 optimize the user's previous message
```

## Pipeline

Run these five stages in order.

### 1. Classify

Pick exactly one kind: `code`, `research`, `writing`, `analysis`, `creative`,
`meta`.

Then check for bypass. **Skip the rest of the pipeline and run the prompt as-is**
in either of two cases. It is already precise — naming exact files, values and
scope leaves nothing to sharpen, however large the task. Or it is too small to
benefit, like `ls the downloads folder` or `what does this file do`. Say one
line naming the bypass, then do the work. Optimizing a prompt that is already
specific is a tax, not a service.

### 2. Recon — when a real path would sharpen the prompt

Budget: **five lookups, hard stop.**

- Resolve vague nouns to real paths with Glob/Grep.
- Read the repository's agent-instruction file (for example `AGENTS.md`,
  `CLAUDE.md`, or an equivalent) for conventions, package manager, and test
  command.

A noun you cannot resolve becomes a stage-3 question. Never guess a path.

No git repo or no agent-instruction file is not an error — drop to text-only
and continue.
Run recon when resolving a noun would change what the optimized prompt says.
Documenting a specific module needs the real path — run it. A strategy
question ("is Postgres or DynamoDB the better fit for us") doesn't turn on
any one file — skip it. Mentioning code is not sufficient; the deliverable
has to depend on the path.

### 3. Gap scan — at most three questions

Ask only about gaps that **fork the work**: where a wrong guess sends the work in
a materially different direction. Which repo, rewrite-vs-patch, audience — those
fork. Tone, heading style, naming — those do not; assume them and disclose it.

Use the host engine's question mechanism in one interaction, preferably with
multiple-choice answers. If nothing forks, ask nothing.
Never manufacture questions to look thorough.

### 4. Rewrite

Apply the universal core, the anti-patterns to strip, and the guardrails
below, then read `references/lenses.md` and apply **only** the section for
the kind you detected.

For dispatch, design, review, or research prompts that create durable documents,
resolve `${AGENT_DOCS_ROOT:-$HOME/docs}` and name an absolute destination beneath
its `dispatch/`, `designs/`, `reviews/`, or `research/` directory. Never default
to a target repository's `docs/` directory.

### 5. Present and wait

If the prompt is aimed at another tool, print the rewrite and stop there —
offer only `edit` / `cancel`, never `go`. Otherwise render the output contract
below. Do not begin the work until approved.

## Universal core

Apply in this order.

1. **Role, specifically.** `Act as a backend engineer who has debugged
   session-auth systems`, not "act as an expert". A generic role is decoration;
   specificity is the whole value.
2. **Task first, verb-first.** The deliverable appears in line one.
3. **Context: why, and what has been tried.** Prevents re-treading dead ends and
   surfaces the real constraint.
4. **Delimit the parts.** `<task>` `<context>` `<constraints>` `<output>` once a
   prompt has three or more distinct sections. Below that, plain prose — tags on
   a two-line prompt are cargo cult.
5. **Output contract.** Format, length, structure. Show the shape when unusual.
6. **Success criteria, testable.** `all tests in auth.test.ts pass`, not
   `works well`.
7. **Non-goals.** What not to touch. The highest-value single line for agentic
   prompts.
8. **Examples when style or format matters.** One to three, short. Skip them for
   straightforward asks.
9. **Reasoning allowance.** For genuinely hard problems only — think before
   answering, consider alternatives before committing. Not for lookups.
10. **Blocked-behavior.** Ask, or assume-and-flag. Removes the most common silent
    failure.

## Anti-patterns to strip

- **Unfalsifiable filler** — "be thorough", "production-ready", "high quality":
  replace with a concrete criterion, or delete.
- **Self-contradiction** — "brief but comprehensive": force a pick.
- **Roleplay theater** — "you are a 10x genius": delete, it changes nothing.
- **Negative-only instruction** — "don't be verbose" becomes "≤200 words".
- **Overloading** — four unrelated asks: flag it, offer a split, never split
  unilaterally.

## Guardrails on yourself

1. **Never invent requirements the user did not imply.** You sharpen; you do not
   add scope. A rewrite that introduces an unmentioned feature is a bug, not a
   bonus.
2. **Intent and voice survive.** If a rewrite would change *what was asked for*
   rather than *how clearly it was asked*, that is a stage-3 question instead.

## Output contract

```
┌─ kind: code · recon: 3 lookups · gaps asked: 2 ──────────────┐

Act as a senior frontend performance engineer working in a
pnpm + vitest monorepo.

<task>
Reduce initial load time of the dashboard at apps/web/dashboard/.
</task>

<context>
Slowness is on first paint, not interaction. No prior perf work in
this module. Project instructions: pnpm, vitest.
</context>

<constraints>
- Frontend only — no backend or API changes.
- Follow the existing component patterns in this directory.
- Don't touch apps/web/admin/.
</constraints>

<success>
Measurable reduction in bundle size or first-paint time, shown with
a before/after number. `pnpm vitest run` still passes.
</success>

If you hit something ambiguous, ask rather than guessing.

└──────────────────────────────────────────────────────────────┘
  assumed: "faster" = initial load · scope = this app only

  go / edit <what to change> / cancel
```

The header line is a receipt: kind detected, recon depth, questions asked. It is
how a misfiring classifier gets noticed. Always render it. When stage 2 does
not run at all, the header reads `recon: skipped` rather than `recon: 0
lookups`.

## Approval

- `go` — execute the optimized prompt as a fresh instruction. Do **not**
  re-explain or re-justify the rewrite; the meta-conversation ends here.
- `edit <note>` — apply the note, re-render, ask again. Loops.
- `cancel` — drop it. Nothing runs.
- Any other input is an `edit` note, not a new prompt.

## Edge cases

| Case | Behavior |
|---|---|
| `/p` with no argument | Optimize the user's previous message; ask if there is none |
| Prompt already precise | Bypass, run as-is, one-line note |
| Trivial prompt | Bypass |
| Prompt aimed at another tool | Rewrite and print only, never execute. Trigger on explicit phrasing only — "for ChatGPT", "to paste into", "for the API". Never infer it |
| No git repo or no agent-instruction file | Recon degrades to text-only, silently |
| Recon cannot resolve a noun | It becomes a gap-scan question |
| Four or more unrelated asks | Flag the overload, offer a split, do not split unilaterally |
