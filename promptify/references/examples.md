# Regression cases

Four hand-run cases. After any edit to `SKILL.md` or `references/lenses.md`, run
each raw prompt through the pipeline and check the behavior matches. This is a
read-and-judge check; there is no automated assertion on prose quality.

The optimized-prompt blocks below are hand-authored expected outputs, not
captured runs — none of the four cases has actually been executed yet.

### Case 1: vague code prompt

Exercises recon and the gap scan.

**Raw:** `/p the export keeps timing out`

**Expected behavior:** classifies `code`; runs recon and resolves "the export"
to a real path; asks 1–3 forking questions (which export, and whether "timing
out" means a hard request timeout or just slow completion); the rewrite names
actual paths and a real verify command; the receipt header reports non-zero
recon and question counts.

**Optimized:**

```
Act as a backend engineer who owns the reporting pipeline in a
Django + pytest service.

<task>
Fix the CSV export in src/reports/export.py timing out for date
ranges longer than 90 days.
</task>

<constraints>
- Export logic only — don't touch the scheduling cron in
  src/reports/scheduler.py.
- Keep the existing streaming-response pattern; don't buffer the
  full export in memory.
</constraints>

<success>
A 12-month export completes in under 30 seconds.
`pytest src/reports/tests/test_export.py` still passes.
</success>

Ask before changing the export's public API; don't guess at it.
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

**Expected behavior:** classifies `research`; **zero** recon lookups, because
the deliverable is a strategy assessment that doesn't turn on any specific
file; the receipt header shows `recon: skipped`; the research lens supplies
source bar, recency window, and the requirement to report conflicting sources
rather than silently resolving them.

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
