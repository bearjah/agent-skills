# promptify — design

**Date:** 2026-07-30
**Status:** approved, ready for implementation plan

## Problem

Raw prompts typed in a hurry are underspecified: they omit the role, the scope
boundary, the definition of done, and what to do when blocked. The result is
work that drifts, over-reaches, or stops short. `promptify` is a wrapper that
rewrites a raw prompt using prompt-engineering best practices, shows the result,
and runs it on approval.

## Decisions

| Decision | Choice |
|---|---|
| Output mode | Show the rewrite, then execute on approval |
| Domain | Any — the skill classifies the prompt and applies a matching lens |
| Missing information | Ask up to 3 targeted questions before rewriting |
| Grounding | Light recon (≤5 lookups) for code and analysis prompts |
| Packaging | Skill holds the logic; a thin command delegates to it |
| Rule storage | Universal core in `SKILL.md`; domain lenses in `references/lenses.md`, read on demand |

## Architecture

```
~/claude-skills/promptify/            source of truth (git)
├── SKILL.md                          pipeline + universal checklist (~150 lines)
├── references/
│   ├── lenses.md                     the 5 domain rule sets (~150 lines)
│   └── examples.md                   before/after pairs, double as test cases
└── commands/p.md                     thin delegating command

~/.claude/skills/promptify   -> symlink to ~/claude-skills/promptify
~/.claude/commands/p.md      -> symlink to ~/claude-skills/promptify/commands/p.md
~/.claude/CLAUDE.md          + 2 lines registering the /promptify trigger
```

The symlink-out-of-`~/claude-skills` shape matches the existing `claude-dispatch`
setup, so the skill is version-controlled rather than living loose in `~/.claude`.

Three entry points, one code path:

- `/p <raw prompt>` — short form, the common case
- `/promptify <raw prompt>` — explicit form
- natural language ("sharpen this prompt", "optimize this before running") —
  auto-triggered by the skill's `description` field

`SKILL.md` frontmatter follows the existing `graphify` convention: `name`,
`description`, `trigger`.

## Pipeline

Five stages, each with a stop condition that keeps the wrapper a wrapper.

### 1. Classify

Assign one of: `code`, `research`, `writing`, `analysis`, `creative`, `meta`.

Bypass check runs here. A prompt that is already precise, or trivially small
(`ls the downloads folder`), runs as-is with a one-line note. Without this rule
the wrapper becomes a tax on every short prompt.

### 2. Recon — `code` and `analysis` only

Resolve vague nouns to real paths; read `CLAUDE.md` for conventions and the test
command. Hard stop at 5 lookups. A noun that stays unresolved becomes a
stage-3 question rather than a guess.

`research`, `writing`, and `creative` prompts skip this stage entirely — there is
rarely anything on disk worth grounding them against.

Absent git repo or `CLAUDE.md`: degrade silently to text-only. Not an error.

### 3. Gap scan — ask at most 3 questions

Only gaps that *fork the work* qualify. A missing tone preference is assumed
silently and disclosed; a missing "which repo" is asked. One `AskUserQuestion`
call, multiple choice. Zero qualifying gaps means zero questions — do not
manufacture them to look thorough.

### 4. Rewrite

Apply the universal core, then read `references/lenses.md` and apply the section
for the detected kind only.

### 5. Present and approve

Render the output contract below, then wait.

## The rule set

### Universal core — applied in order

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
8. **Examples when style or format matters.** One to three, short. Skipped for
   straightforward asks.
9. **Reasoning allowance.** For genuinely hard problems only — think before
   answering, consider alternatives before committing. Not for lookups.
10. **Blocked-behavior.** Ask, or assume-and-flag. Removes the most common
    silent failure.

### Anti-patterns stripped

- **Unfalsifiable filler** — "be thorough", "production-ready", "high quality":
  replaced with a concrete criterion, or deleted.
- **Self-contradiction** — "brief but comprehensive": forced to pick.
- **Roleplay theater** — "you are a 10x genius": deleted, changes nothing.
- **Negative-only instruction** — "don't be verbose" becomes "≤200 words".
- **Overloading** — four unrelated asks: flagged, split offered, never split
  unilaterally.

### Domain lenses

```
code      files in scope · don't-touch list · verify command
          follow existing patterns · plan-first or just-do
research  source quality bar · recency window · depth
          cite claims · how to handle conflicting sources
writing   audience · register · length target · structure
          anti-references (what to not sound like)
analysis  where the data is · method · assumptions to surface
          output shape · significance bar
creative  constraints as fuel · references and anti-references
          how many options · what makes one win
```

`meta` (prompts about prompts, agent instructions, system prompts) uses the
`writing` lens plus the `code` lens's scope rules.

### Guardrails on the optimizer itself

1. **Never invent requirements the user did not imply.** The optimizer sharpens;
   it does not add scope. A rewrite that introduces an unmentioned feature is a
   bug, not a bonus.
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
this module. Project conventions in CLAUDE.md: pnpm, vitest.
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

The header is a receipt: kind detected, recon depth, questions asked. It is how
a misfiring classifier gets noticed.

### Approval semantics

- `go` — execute the optimized prompt as a fresh instruction. Do not re-explain
  or re-justify the rewrite; the meta-conversation ends at approval.
- `edit <note>` — apply the note, re-render, ask again. Loops.
- `cancel` — drop it. Nothing runs.
- Any other input is treated as an `edit` note, not as a new prompt.

## Edge cases

| Case | Behavior |
|---|---|
| `/p` with no argument | Optimize the user's previous message; ask if there is none |
| Prompt already precise | Bypass, run as-is, one-line note |
| Trivial prompt | Bypass |
| Prompt aimed at another tool | Rewrite and print only, never execute. Detected from explicit phrasing only — "for ChatGPT", "to paste into", "for the API". Never inferred. |
| No git repo or no `CLAUDE.md` | Recon degrades to text-only, silently |
| Recon cannot resolve a noun | Becomes a gap-scan question |
| Four or more unrelated asks | Flag the overload, offer a split, do not split unilaterally |

## Verification

`references/examples.md` holds before/after pairs that double as manual
regression cases. Four are required:

1. A vague code prompt — exercises recon and the gap scan.
2. An already-precise prompt — must bypass.
3. A multi-domain prompt — classifier check.
4. A non-code prompt — must skip recon.

Running these four by hand after any edit to the rule set is the regression
check. There is no automated test harness; the skill is prose, and the cases are
read-and-judge.

## Out of scope

- Auto-optimizing every prompt via a `UserPromptSubmit` hook.
- Multi-candidate generation with self-critique.
- Deep exploration via a subagent before rewriting.
- Any persistence of past prompts or learned preferences.
