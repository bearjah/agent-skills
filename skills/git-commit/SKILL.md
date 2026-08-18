---
name: git-commit
description: Create safe, focused Git commits with useful messages grounded in the actual diff. Use when the user asks to commit changes, prepare a commit, write a commit message, split work into logical commits, or invokes git commit.
---

# Git Commit

Create one coherent commit at a time. Preserve unrelated work and make the
history explain why the change exists, not merely what the diff contains.

## 1. Establish the scope

Read repository instructions, then inspect:

```bash
git status --short --branch
git diff --stat
git diff
git diff --cached
git log -10 --format='%s'
```

Treat an existing staged set as user intent. Do not add unstaged changes to it
unless the user asks or they are unambiguously part of the same change. If
nothing is staged, divide the work into logical commits and stage exact paths
or hunks. Do not use broad staging such as `git add -A` by default.

## 2. Check safety and coherence

Inspect every staged file and the full staged diff. Stop and ask before
committing when scope or ownership is ambiguous. Do not commit:

- Secrets, credentials, private keys, or local environment files.
- Unresolved conflicts or unrelated user changes.
- Generated artifacts that the repository does not normally track.

Keep one logical change per commit. Do not edit the implementation merely to
tidy the commit unless the user also requested implementation work. Run the
relevant checks required by repository instructions. Report checks that could
not run; never claim they passed.

## 3. Write a useful message

Match the repository's established message style. Use Conventional Commits only
when repository instructions or recent history use them.

Write a specific, imperative subject that describes the outcome or intent. Aim
for 72 characters or fewer and omit the trailing period. Avoid vague subjects
such as `fix bug`, `updates`, or `misc changes`.

Add a body when the reason is not obvious. Include the context that will help a
future investigator:

- The problem or trigger and its impact.
- Why this approach was chosen, including important constraints or tradeoffs.
- An exact error, command, or observable symptom when it makes the commit more
  searchable or reproducible.
- Follow-ups or non-goals when they prevent a misleading interpretation.

Do not narrate the diff line by line or add generic filler. Add issue references
and trailers only when supplied by the task or repository; never invent them.

For example:

```text
Prevent duplicate booking confirmations

Two workers could confirm the same pending request before either update
became visible, creating duplicate bookings. Move the status check and insert
into one transaction so the database arbitrates the race.

Reproduced with: go test -race ./internal/request -run TestConcurrentConfirm
```

## 4. Commit and verify

Before committing, run `git diff --cached --check` and re-read
`git diff --cached`. Create the commit without unsafe shell interpolation.

Never change Git configuration, bypass hooks, amend, reset, force-push, or push
unless the user explicitly requested that action. If a hook fails or modifies
files, re-inspect the working tree and staged diff; do not skip the hook or
amend automatically.

After committing, inspect `git show --stat --oneline HEAD` and
`git status --short --branch`. Report the commit hash and subject, checks run,
and any uncommitted changes left behind.
