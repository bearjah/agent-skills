# promptify Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `promptify` skill that rewrites a raw prompt using prompt-engineering best practices, shows the rewrite, and runs it on approval.

**Architecture:** A prose skill plus a shell installer. `SKILL.md` holds the always-loaded pipeline and universal rule set; `references/lenses.md` holds per-domain rules read only for the detected kind; `commands/p.md` is a thin delegator. `install.sh` symlinks both into `~/.claude` and appends an idempotent trigger block to `~/.claude/CLAUDE.md`. A bash test suite covers the mechanical surface — frontmatter, required sections, line budgets, symlinks, installer idempotency. The prose itself is verified by four hand-run regression cases in `references/examples.md`.

**Tech Stack:** Markdown, bash (no dependencies beyond coreutils, awk, grep).

## Global Constraints

- Repo `~/claude-skills`, branch `promptify`. All paths below are relative to `~/claude-skills/promptify/`.
- Spec of record: `DESIGN.md` in this directory. Rule text is **copied verbatim** from it, never re-invented.
- Bash scripts: `#!/usr/bin/env bash`, `set -euo pipefail`, matching `claude-dispatch` style.
- Install by **symlink only** — the repo stays the source of truth. Never copy files into `~/.claude`.
- `install.sh` must be idempotent: running it twice leaves exactly one trigger block in `CLAUDE.md`, and must never destroy pre-existing `CLAUDE.md` content (the user's `graphify` block lives there).
- `SKILL.md` ≤ 200 lines. `references/lenses.md` ≤ 200 lines. These are enforced by test.
- Frontmatter keys follow the existing `graphify` convention: `name`, `description`, `trigger`.
- Commit after every task.

---

### Task 1: Test harness and SKILL.md core

**Files:**
- Create: `test/helpers.sh`
- Create: `test/run-tests.sh`
- Create: `test/test_structure.sh`
- Create: `SKILL.md`

**Interfaces:**
- Consumes: nothing.
- Produces: `test/helpers.sh` exporting `fail`, `assert_eq`, `assert_contains`, `assert_file_has`, `assert_max_lines`, `run_test`. `test/run-tests.sh` exporting `$ROOT` (repo dir) to every sourced test file. Later tasks add `test_*` functions to `test/test_structure.sh` and `test/test_install.sh`; the runner discovers them automatically.

- [ ] **Step 1: Write the test harness**

`test/helpers.sh`:

```bash
#!/usr/bin/env bash
# Shared assertions for the promptify test suite.

fail() {
  printf '    FAIL: %s\n' "$1" >&2
  TEST_FAILED=1
}

assert_eq() {
  local actual="$1" expected="$2" label="${3:-}"
  [ "$actual" = "$expected" ] || fail "${label:+$label: }expected '$expected', got '$actual'"
}

assert_contains() {
  local haystack="$1" needle="$2" label="${3:-}"
  case "$haystack" in
    *"$needle"*) ;;
    *) fail "${label:+$label: }expected to contain '$needle', got: $haystack" ;;
  esac
}

# assert_file_has <file> <literal string>
assert_file_has() {
  local file="$1" needle="$2"
  if [ ! -f "$file" ]; then
    fail "missing file: $file"
    return
  fi
  grep -qF -- "$needle" "$file" || fail "$file: expected to contain '$needle'"
}

# assert_max_lines <file> <max>
assert_max_lines() {
  local file="$1" max="$2" n
  if [ ! -f "$file" ]; then
    fail "missing file: $file"
    return
  fi
  n="$(wc -l < "$file")"
  [ "$n" -le "$max" ] || fail "$file: $n lines exceeds budget of $max"
}

run_test() {
  local fn="$1"
  TEST_FAILED=0
  TESTS_RUN=$((TESTS_RUN + 1))
  printf '  %s\n' "$fn"
  "$fn"
  [ "$TEST_FAILED" -eq 0 ] || TESTS_FAILED=$((TESTS_FAILED + 1))
}
```

`test/run-tests.sh`:

```bash
#!/usr/bin/env bash
# Runs every test_* function defined in test/test_*.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT
# shellcheck source=test/helpers.sh
source "$ROOT/test/helpers.sh"

TESTS_RUN=0
TESTS_FAILED=0

for f in "$ROOT"/test/test_*.sh; do
  # shellcheck source=/dev/null
  source "$f"
done

while read -r fn; do
  run_test "$fn"
done < <(declare -F | awk '{print $3}' | grep '^test_' | sort)

printf '\n%d run, %d failed\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
```

`test/test_structure.sh`:

```bash
#!/usr/bin/env bash
# Structural checks on the prose deliverables.

test_skill_frontmatter() {
  assert_file_has "$ROOT/SKILL.md" "name: promptify"
  assert_file_has "$ROOT/SKILL.md" "trigger: /promptify"
  assert_file_has "$ROOT/SKILL.md" "description:"
  assert_eq "$(head -1 "$ROOT/SKILL.md")" "---" "first line of SKILL.md"
}

test_skill_has_required_sections() {
  local s
  for s in "## Pipeline" "## Universal core" "## Anti-patterns" \
           "## Guardrails" "## Output contract" "## Approval" "## Edge cases"; do
    assert_file_has "$ROOT/SKILL.md" "$s"
  done
}

test_skill_describes_all_five_stages() {
  local s
  for s in "1. Classify" "2. Recon" "3. Gap scan" "4. Rewrite" "5. Present"; do
    assert_file_has "$ROOT/SKILL.md" "$s"
  done
}

test_skill_points_at_lenses() {
  assert_file_has "$ROOT/SKILL.md" "references/lenses.md"
}

test_skill_within_line_budget() {
  assert_max_lines "$ROOT/SKILL.md" 200
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `chmod +x test/run-tests.sh && ./test/run-tests.sh`
Expected: FAIL — five failures, all `missing file: .../SKILL.md`.

- [ ] **Step 3: Write SKILL.md**

Copy the rule bodies verbatim from `DESIGN.md` § "The rule set". Full content:

`````markdown
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
when it is already precise, or too small to benefit — `ls the downloads folder`,
`what does this file do`. Say one line naming the bypass, then do the work.
Optimizing a trivial prompt is a tax, not a service.

### 2. Recon — `code` and `analysis` only

Budget: **five lookups, hard stop.**

- Resolve vague nouns to real paths with Glob/Grep.
- Read `CLAUDE.md` for conventions, package manager, test command.

A noun you cannot resolve becomes a stage-3 question. Never guess a path.

No git repo or no `CLAUDE.md` is not an error — drop to text-only and continue.
`research`, `writing`, and `creative` prompts skip this stage entirely.

### 3. Gap scan — at most three questions

Ask only about gaps that **fork the work**: where a wrong guess sends the work in
a materially different direction. Which repo, rewrite-vs-patch, audience — those
fork. Tone, heading style, naming — those do not; assume them and disclose it.

Use one `AskUserQuestion` call, multiple choice. If nothing forks, ask nothing.
Never manufacture questions to look thorough.

### 4. Rewrite

Apply the universal core below, then read `references/lenses.md` and apply
**only** the section for the kind you detected.

### 5. Present and wait

Render the output contract below. Do not begin the work until approved.

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

The header line is a receipt: kind detected, recon depth, questions asked. It is
how a misfiring classifier gets noticed. Always render it.

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
| No git repo or no `CLAUDE.md` | Recon degrades to text-only, silently |
| Recon cannot resolve a noun | It becomes a gap-scan question |
| Four or more unrelated asks | Flag the overload, offer a split, do not split unilaterally |
`````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./test/run-tests.sh`
Expected: PASS — `5 run, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add test/ SKILL.md
git commit -m "feat: add promptify SKILL.md core and test harness"
```

---

### Task 2: Domain lenses

**Files:**
- Create: `references/lenses.md`
- Modify: `test/test_structure.sh` (append new test functions)

**Interfaces:**
- Consumes: `SKILL.md` stage 4 reads this file and applies exactly one section.
- Produces: one `## <kind>` section per kind, where kind ∈ {code, research, writing, analysis, creative, meta}. `SKILL.md` matches sections by that exact heading text, so headings are lowercase and single-word.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_structure.sh`:

```bash
test_lenses_has_a_section_per_kind() {
  local k
  for k in code research writing analysis creative meta; do
    assert_file_has "$ROOT/references/lenses.md" "## $k"
  done
}

test_lenses_meta_composes_writing_and_code() {
  local body
  body="$(awk '/^## meta$/{f=1;next} /^## /{f=0} f' "$ROOT/references/lenses.md")"
  assert_contains "$body" "writing" "meta section body"
  assert_contains "$body" "code" "meta section body"
}

test_lenses_within_line_budget() {
  assert_max_lines "$ROOT/references/lenses.md" 200
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./test/run-tests.sh`
Expected: FAIL — `missing file: .../references/lenses.md`.

- [ ] **Step 3: Write references/lenses.md**

Content, expanded from `DESIGN.md` § "Domain lenses":

`````markdown
# Domain lenses

Read only the section matching the kind detected in stage 1. Each bullet is a
question to answer in the rewrite — drop any that the raw prompt already settles.

## code

- **Files in scope.** Name real paths found during recon, not "the auth module".
- **Don't-touch list.** Adjacent code, other apps, generated files, migrations.
- **Verify command.** The project's actual test or build command, from
  `CLAUDE.md` or the package manifest.
- **Follow existing patterns.** Point at a sibling file that models the style.
- **Plan-first or just-do.** Big blast radius means plan first; a one-file fix
  does not.
- **On blocked.** Ask, or assume-and-flag. Say which.

## research

- **Source quality bar.** Primary sources, peer-reviewed, official docs, or
  anything goes.
- **Recency window.** "Since 2024", "current stable release", or timeless.
- **Depth.** A quick orientation versus an exhaustive survey.
- **Cite claims.** Require links or references for factual assertions.
- **Conflicting sources.** Report the disagreement rather than silently picking.
- **Confidence marking.** Flag what is established versus contested.

## writing

- **Audience.** Who reads it and what they already know.
- **Register.** Formal, conversational, technical, marketing.
- **Length target.** A number, not "concise".
- **Structure.** Headings, prose, list — and roughly how it opens and closes.
- **Anti-references.** What it must not sound like. Often more useful than
  positive style direction.
- **Draft or final.** Whether polish matters yet.

## analysis

- **Where the data is.** Exact file, table, or query.
- **Method.** The comparison, aggregation, or model to apply.
- **Assumptions to surface.** Require them stated rather than buried.
- **Output shape.** Table, prose, chart, number with an interval.
- **Significance bar.** What counts as a real difference versus noise.

## creative

- **Constraints as fuel.** Form, length, medium, forbidden moves. Constraints
  generate; open briefs stall.
- **References and anti-references.** Two or three of each.
- **How many options.** A number, so the work stops.
- **What makes one win.** The criterion used to pick among them.

## meta

Prompts about prompts: system prompts, agent instructions, other skills.

Apply the **writing** lens for audience, register, and structure, plus these
from the **code** lens:

- **Files in scope** — which prompt or instruction file is being changed.
- **Don't-touch list** — sections that must survive untouched.

Then add: state which model or agent consumes it, and what observable behavior
change counts as success.
`````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./test/run-tests.sh`
Expected: PASS — `8 run, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add references/lenses.md test/test_structure.sh
git commit -m "feat: add promptify domain lenses"
```

---

### Task 3: Regression examples

**Files:**
- Create: `references/examples.md`
- Modify: `test/test_structure.sh` (append new test functions)

**Interfaces:**
- Consumes: the rules in `SKILL.md` and `references/lenses.md` — each case demonstrates one.
- Produces: exactly four `### Case N:` sections, each with `**Raw:**`, `**Expected behavior:**`, and `**Optimized:**` subsections. The count of four is asserted by test; adding a fifth case means updating `test_examples_has_four_cases`.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_structure.sh`:

```bash
test_examples_has_four_cases() {
  local n
  n="$(grep -cE '^### Case [0-9]+:' "$ROOT/references/examples.md" 2>/dev/null || printf '0')"
  assert_eq "$n" "4" "case count in examples.md"
}

test_examples_cover_the_required_scenarios() {
  local s
  for s in "vague code" "already precise" "multi-domain" "non-code"; do
    assert_file_has "$ROOT/references/examples.md" "$s"
  done
}

test_examples_each_case_has_all_three_parts() {
  local raw expected optimized
  raw="$(grep -cF '**Raw:**' "$ROOT/references/examples.md" 2>/dev/null || printf '0')"
  expected="$(grep -cF '**Expected behavior:**' "$ROOT/references/examples.md" 2>/dev/null || printf '0')"
  optimized="$(grep -cF '**Optimized:**' "$ROOT/references/examples.md" 2>/dev/null || printf '0')"
  assert_eq "$raw" "4" "Raw sections"
  assert_eq "$expected" "4" "Expected behavior sections"
  assert_eq "$optimized" "4" "Optimized sections"
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./test/run-tests.sh`
Expected: FAIL — case count `expected '4', got '0'`.

- [ ] **Step 3: Write references/examples.md**

`````markdown
# Regression cases

Four hand-run cases. After any edit to `SKILL.md` or `references/lenses.md`, run
each raw prompt through the pipeline and check the behavior matches. This is a
read-and-judge check; there is no automated assertion on prose quality.

### Case 1: vague code prompt

Exercises recon and the gap scan.

**Raw:** `/p make the dashboard faster`

**Expected behavior:** classifies `code`; runs recon and resolves "the dashboard"
to a real path; asks 1–3 forking questions (which app, which kind of slow); the
rewrite names actual paths and a real verify command; the receipt header reports
non-zero recon and question counts.

**Optimized:**

```
Act as a senior frontend performance engineer working in a
pnpm + vitest monorepo.

<task>
Reduce initial load time of the dashboard at apps/web/dashboard/.
</task>

<constraints>
- Frontend only — no backend or API changes.
- Don't touch apps/web/admin/.
</constraints>

<success>
Before/after number for bundle size or first paint.
`pnpm vitest run` still passes.
</success>

If you hit something ambiguous, ask rather than guessing.
```

### Case 2: already precise prompt

Must bypass. This is the case that keeps the wrapper from becoming a tax.

**Raw:** `/p In src/auth/session.ts, change the token TTL from 3600 to 900 and update the assertion in src/auth/session.test.ts. Don't touch anything else.`

**Expected behavior:** bypass fires. No recon, no questions, no rewrite. One line
naming the bypass, then the work starts immediately.

**Optimized:** none — the prompt runs as written.

### Case 3: multi-domain prompt

Classifier check. Two kinds are plausible; exactly one lens must be chosen.

**Raw:** `/p write up how our caching layer works for the new hires`

**Expected behavior:** classifies `writing`, not `code` — the deliverable is a
document, and the code is the subject rather than the target. Recon still runs
because grounding the doc in real paths helps, but the writing lens drives the
rewrite: audience (new hires), length, structure. If the classifier picks `code`
here, the rule needs sharpening.

**Optimized:**

```
Act as a staff engineer writing onboarding documentation.

<task>
Explain how the caching layer in src/cache/ works, for engineers in
their first week who know the language but not this system.
</task>

<output>
800–1200 words. Opens with the one-paragraph mental model, then the
request path, then the invalidation rules. Prose with headings, not
a bullet dump.
</output>

<success>
A new hire can predict what happens on a cache miss without reading
the source.
</success>
```

### Case 4: non-code prompt

Must skip recon entirely.

**Raw:** `/p research whether we should move off REST to GraphQL`

**Expected behavior:** classifies `research`; **zero** recon lookups; the receipt
header shows `recon: skipped`; the research lens supplies source bar, recency
window, and the requirement to report conflicting sources rather than silently
resolving them.

**Optimized:**

```
Act as a pragmatic API architect with no stake in either technology.

<task>
Assess whether migrating our REST API to GraphQL is justified.
</task>

<constraints>
- Sources from 2024 or later; prefer post-mortems and migration
  reports over vendor material.
- Where sources disagree, report the disagreement — don't pick a
  winner silently.
</constraints>

<output>
The case for, the case against, then what it depends on for us.
Under 700 words. Mark each claim as established or contested.
</output>
```
`````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./test/run-tests.sh`
Expected: PASS — `11 run, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add references/examples.md test/test_structure.sh
git commit -m "feat: add promptify regression cases"
```

---

### Task 4: The `/p` command

**Files:**
- Create: `commands/p.md`
- Modify: `test/test_structure.sh` (append new test functions)

**Interfaces:**
- Consumes: the `promptify` skill by name.
- Produces: a command file whose body passes `$ARGUMENTS` through to the skill. `install.sh` in Task 5 symlinks this exact path to `~/.claude/commands/p.md`.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_structure.sh`:

```bash
test_command_frontmatter() {
  assert_eq "$(head -1 "$ROOT/commands/p.md")" "---" "first line of p.md"
  assert_file_has "$ROOT/commands/p.md" "description:"
  assert_file_has "$ROOT/commands/p.md" "argument-hint:"
}

test_command_delegates_to_the_skill() {
  assert_file_has "$ROOT/commands/p.md" "promptify"
  assert_file_has "$ROOT/commands/p.md" '$ARGUMENTS'
}

test_command_stays_thin() {
  assert_max_lines "$ROOT/commands/p.md" 20
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./test/run-tests.sh`
Expected: FAIL — `missing file: .../commands/p.md`.

- [ ] **Step 3: Write commands/p.md**

```markdown
---
description: "Optimize my prompt using prompt-engineering best practices, then run it on approval"
argument-hint: "<your raw prompt>"
---

Invoke the Skill tool with `skill: "promptify"` before doing anything else.

The raw prompt to optimize:

$ARGUMENTS

If the above is empty, optimize my previous message instead.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./test/run-tests.sh`
Expected: PASS — `14 run, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add commands/p.md test/test_structure.sh
git commit -m "feat: add /p command delegating to promptify"
```

---

### Task 5: Installer

**Files:**
- Create: `install.sh`
- Create: `test/test_install.sh`

**Interfaces:**
- Consumes: `SKILL.md`, `commands/p.md` — both must exist before install is meaningful.
- Produces: `~/.claude/skills/promptify` → symlink to the repo directory; `~/.claude/commands/p.md` → symlink to `commands/p.md`; a marker-delimited block in `~/.claude/CLAUDE.md` bounded by `<!-- promptify:begin -->` and `<!-- promptify:end -->`. Those two marker strings are the idempotency contract — the test asserts on them literally.

- [ ] **Step 1: Write the failing tests**

`test/test_install.sh`:

```bash
#!/usr/bin/env bash
# Installer behavior, exercised against a throwaway HOME.

test_install_creates_symlinks() {
  local home
  home="$(mktemp -d)"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  [ -L "$home/.claude/skills/promptify" ] || fail "skill symlink missing"
  [ -L "$home/.claude/commands/p.md" ] || fail "command symlink missing"
  assert_eq "$(readlink "$home/.claude/skills/promptify")" "$ROOT" "skill link target"
  assert_eq "$(readlink "$home/.claude/commands/p.md")" "$ROOT/commands/p.md" "command link target"
  rm -rf "$home"
}

test_install_registers_the_trigger() {
  local home
  home="$(mktemp -d)"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  assert_file_has "$home/.claude/CLAUDE.md" "promptify"
  assert_file_has "$home/.claude/CLAUDE.md" "<!-- promptify:begin -->"
  assert_file_has "$home/.claude/CLAUDE.md" "<!-- promptify:end -->"
  rm -rf "$home"
}

test_install_is_idempotent() {
  local home n
  home="$(mktemp -d)"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  n="$(grep -cF '<!-- promptify:begin -->' "$home/.claude/CLAUDE.md")"
  assert_eq "$n" "1" "trigger block count after two installs"
  rm -rf "$home"
}

test_install_preserves_existing_claude_md() {
  local home
  home="$(mktemp -d)"
  mkdir -p "$home/.claude"
  printf '# graphify\nkeep me\n' > "$home/.claude/CLAUDE.md"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  assert_file_has "$home/.claude/CLAUDE.md" "keep me"
  assert_file_has "$home/.claude/CLAUDE.md" "# graphify"
  rm -rf "$home"
}

test_install_handles_claude_md_without_trailing_newline() {
  local home n
  home="$(mktemp -d)"
  mkdir -p "$home/.claude"
  printf 'no trailing newline' > "$home/.claude/CLAUDE.md"
  HOME="$home" bash "$ROOT/install.sh" >/dev/null
  assert_file_has "$home/.claude/CLAUDE.md" "no trailing newline"
  n="$(grep -cF '<!-- promptify:begin -->' "$home/.claude/CLAUDE.md")"
  assert_eq "$n" "1" "trigger block count"
  rm -rf "$home"
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./test/run-tests.sh`
Expected: FAIL — all five install tests error on the missing `install.sh`.

- [ ] **Step 3: Write install.sh**

```bash
#!/usr/bin/env bash
# Symlink promptify into ~/.claude and register its trigger in CLAUDE.md.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
MD="$CLAUDE_DIR/CLAUDE.md"
BEGIN='<!-- promptify:begin -->'
END='<!-- promptify:end -->'

mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/commands"

ln -sfn "$HERE" "$CLAUDE_DIR/skills/promptify"
ln -sfn "$HERE/commands/p.md" "$CLAUDE_DIR/commands/p.md"

touch "$MD"

# Drop any previous block so re-running never duplicates it.
if grep -qF "$BEGIN" "$MD"; then
  awk -v b="$BEGIN" -v e="$END" '
    index($0, b) { skip = 1 }
    !skip        { print }
    index($0, e) { skip = 0 }
  ' "$MD" > "$MD.tmp"
  mv "$MD.tmp" "$MD"
fi

# Guarantee a newline before appending, so the block never glues onto prior text.
if [ -s "$MD" ] && [ "$(tail -c1 "$MD" | wc -l)" -eq 0 ]; then
  printf '\n' >> "$MD"
fi

cat >> "$MD" <<EOF
$BEGIN
# promptify
- **promptify** (\`~/.claude/skills/promptify/SKILL.md\`) - optimize a raw prompt, then run it on approval. Trigger: \`/promptify\` or \`/p\`
When the user types \`/promptify\` or \`/p\`, invoke the Skill tool with \`skill: "promptify"\` before doing anything else.
$END
EOF

printf 'installed:\n  %s\n  %s\n  %s (trigger block)\n' \
  "$CLAUDE_DIR/skills/promptify" \
  "$CLAUDE_DIR/commands/p.md" \
  "$MD"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `chmod +x install.sh && ./test/run-tests.sh`
Expected: PASS — `19 run, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add install.sh test/test_install.sh
git commit -m "feat: add idempotent promptify installer"
```

---

### Task 6: README, real install, and the manual regression pass

**Files:**
- Create: `README.md`
- Modify: `~/.claude/CLAUDE.md` (via `install.sh`, not by hand)

**Interfaces:**
- Consumes: every prior task.
- Produces: a working installation. No later task depends on this one.

- [ ] **Step 1: Write README.md**

```markdown
# promptify

Rewrites a raw prompt using prompt-engineering best practices, shows the
rewrite, and runs it on approval.

## Install

```bash
./install.sh
```

Symlinks `~/.claude/skills/promptify` and `~/.claude/commands/p.md` into this
repo, and appends a trigger block to `~/.claude/CLAUDE.md`. Idempotent — safe to
re-run after a `git pull`.

## Use

```
/p make the dashboard faster       short form
/promptify <raw prompt>            explicit form
/p                                 optimize my previous message
```

It classifies the prompt, does bounded recon for code and analysis prompts, asks
up to three questions where a wrong guess would fork the work, rewrites, and then
waits for `go` / `edit <note>` / `cancel`.

Already-precise and trivial prompts bypass the pipeline and run as-is.

## Layout

| Path | Role |
|---|---|
| `SKILL.md` | Pipeline, universal rules, output contract — always loaded |
| `references/lenses.md` | Per-domain rules — read only for the detected kind |
| `references/examples.md` | Four regression cases, run by hand |
| `commands/p.md` | Thin `/p` delegator |
| `DESIGN.md` | The approved spec |
| `PLAN.md` | The implementation plan |

## Test

```bash
./test/run-tests.sh
```

Covers frontmatter, required sections, line budgets, symlinks, and installer
idempotency. Prose quality is checked by hand against `references/examples.md`.
```

- [ ] **Step 2: Run the full suite one more time**

Run: `./test/run-tests.sh`
Expected: PASS — `19 run, 0 failed`.

- [ ] **Step 3: Install for real**

Run: `./install.sh`
Expected output names three paths. Then verify the pre-existing `graphify` block
survived:

Run: `grep -c graphify ~/.claude/CLAUDE.md`
Expected: a non-zero count.

- [ ] **Step 4: Run the four regression cases by hand**

In a fresh session, run each `**Raw:**` prompt from `references/examples.md` and
confirm the `**Expected behavior:**` holds. The two that fail most often:

- Case 2 must **bypass** — if it rewrites an already-precise prompt, tighten the
  bypass rule in `SKILL.md` stage 1.
- Case 4 must show `recon: skipped` — if it runs lookups on a research prompt,
  tighten the stage 2 gate.

Fix `SKILL.md` or `references/lenses.md` inline for any miss, then re-run the
suite and the four cases.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: add promptify README"
```

---

## Self-review

**Spec coverage** — every `DESIGN.md` section maps to a task:

| Spec section | Task |
|---|---|
| Architecture / file layout | 1–5 (files created), 6 (README documents it) |
| Pipeline, all five stages | 1 (`SKILL.md`), asserted by `test_skill_describes_all_five_stages` |
| Universal core, 10 rules | 1 |
| Anti-patterns stripped | 1 |
| Domain lenses, 6 kinds | 2 |
| Guardrails on the optimizer | 1 |
| Output contract + receipt header | 1 |
| Approval semantics | 1 |
| Edge cases table | 1 |
| Verification / 4 regression cases | 3 (written), 6 (run) |
| Symlinks + `CLAUDE.md` registration | 5 |
| Out of scope (hook, multi-candidate, subagent recon, persistence) | no task — correctly absent |

**Placeholder scan** — no TBD/TODO. Every prose deliverable is given in full; every bash step has runnable code; no step says "similar to Task N".

**Type consistency** — checked across tasks: helper names (`fail`, `assert_eq`, `assert_contains`, `assert_file_has`, `assert_max_lines`, `run_test`) are defined in Task 1 and used unchanged in Tasks 2–5. `$ROOT` is exported by `run-tests.sh` and referenced by every test file. The marker strings `<!-- promptify:begin -->` / `<!-- promptify:end -->` are identical in `install.sh` and `test_install.sh`. Section headings asserted in tests (`## Pipeline`, `## Universal core`, `## Anti-patterns`, `## Guardrails`, `## Output contract`, `## Approval`, `## Edge cases`) match the headings actually written in `SKILL.md`; lens headings (`## code` … `## meta`) match those in `lenses.md`.

One consistency fix applied during review: `SKILL.md`'s guardrails heading is `## Guardrails on yourself`, and the test asserts on the prefix `## Guardrails`, so the substring match holds.
