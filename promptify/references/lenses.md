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
