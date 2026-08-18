---
name: finalize-work
description: "Use when a dispatched work item is finished and its session is about to be closed — \"finalize this work\", \"wrap up\", \"ready to close this session\", \"clean up before I close this\" — or when asked what a worktree session left behind, whether its documents and INDEX row are true, or whether it is safe to close."
---

# finalize-work

Close the loop `/dispatch` opened. A dispatched session writes documents to
`~/docs/designs/YYYY-MM-DD-<slug>/` and is then abandoned: nothing reconciles them
against what shipped, and the worktree lives forever. Run this last, inside the
finishing worktree — after `superpowers:finishing-a-development-branch` has decided
*how to integrate* the code. This is the paperwork, not that decision.

## Authority

| You may | You may not |
|---|---|
| Edit documents under `~/docs/designs/<item>/` | Delete or move any file |
| Add or update this item's `INDEX.md` row | Remove a worktree or delete a branch |
| Commit `~/docs` by explicit pathspec | Push anything, anywhere |
| Read GitHub via `gh pr view` / `gh pr list` | Open, close, comment on or edit a PR or issue |

Everything on the right leaves as a paste-ready command for the human, in Phase 2.

## 0. Locate the dispatch
```bash
# locate: run from anywhere inside the finishing worktree
top=$(git rev-parse --show-toplevel) || exit 1
branch=$(git rev-parse --abbrev-ref HEAD)
root=""
for candidate in "${DISPATCH_WORKTREE_ROOT:-}" "$HOME/.claude/worktrees" \
                 "$HOME/.codex/worktrees" "$HOME/.agent-skills/worktrees"; do
  [ -n "$candidate" ] || continue
  case "$top" in "$candidate"/*/*) root="$candidate"; break ;; esac
done
[ -n "$root" ] || { printf 'not a dispatch worktree: %s (branch %s)\n' "$top" "$branch"; exit 1; }
relative=${top#"$root"/}
repo=${relative%%/*}
slug=${relative#*/}
case "$slug" in *'/'*|'') printf 'not a dispatch worktree: %s (branch %s)\n' "$top" "$branch"; exit 1 ;; esac
printf 'repo=%s\nslug=%s\nbranch=%s\n' "$repo" "$slug" "$branch"
find "$root" -mindepth 2 -maxdepth 2 -type d -name "$slug"   # every target this dispatch created
```
Exit 1 means **stop**: report what you found — a plain checkout, on which branch —
and do nothing else. There is no master-session mode; never finalize a work item you
are not sitting in, and never infer one from the shell's cwd, which drifts.

`branch` is often **not** `dispatch/<slug>` — sessions rename before opening a PR.
Normal, and it changes Phase 2: `--cleanup` deletes `dispatch/<slug>`, which is then
not the branch holding the work. Find the documents with
`ls -d ~/docs/designs/*-"$slug"`; no match, or several, is a question for the human.

The `find` command finds only worktrees carrying **this** slug. A session that made another by
hand — a second repo, under a slug of its own — leaves one the glob cannot see, and
its commits may exist on no other machine. Cross-check against what the documents
say, and treat every hit as another target with its own cleanup command:
`grep -ohE 'worktrees/[a-z0-9._-]+/[a-z0-9-]+' ~/docs/designs/<item>/*.md | sort -u`

## Phase 1 — reconcile the documents
Make one todo per numbered item. Work them in order.

1. **Read every document's status line.** `INDEX.md` quotes it **verbatim**, so a
   document with none becomes `not recorded` there. Fix the document, not the quote.
   `grep -n '^\*\*Status:\*\*' ~/docs/designs/<item>/*.md`

2. **Get PR state from `gh`, not from the documents.**
   ```bash
   grep -ohE '#[0-9]{3,6}|https://github\.com/[^ )]+/pull/[0-9]+' \
     ~/docs/designs/<item>/*.md | sort -u          # what the documents claim
   gh pr view <n> --repo <owner>/<repo> \
     --json number,url,state,mergeCommit,mergedAt   # what is true
   gh pr list --repo <owner>/<repo> --head "$branch" --state all \
     --json number,url,state,mergedAt               # PR for the branch, if any
   ```
   A `#nnnn` that turns out to be an issue is fine — say so. Every state you report
   comes from a `gh` call you ran here; one you did not run reads `unverified`. A
   document's prose is never evidence about its own PR.

3. **Flag every document claiming shipped, merged, landed or complete while its PR
   is not `MERGED`** — the check this skill exists for. Give the claim, the real
   state, and the file and line to correct.

4. **Commits with no PR are unfinished work**, even when pushed. Check
   `git -C <wt> log --oneline <base>..HEAD` against step 2's `gh pr list`.

5. **Enumerate what was left undone** — deferred tasks, open questions, findings with
   no work item, blockers. Each lands in exactly one of three places and you name
   which: the document's status line, `INDEX.md` under `## Deferred / not started`,
   or explicitly dropped. Nothing may fall through silently.

6. **Rewrite each status line to carry its evidence** — merged PR as a full URL
   with number, merge commit and merge timestamp; what shipped; what deferred and
   to where. `**Status:** Done` is below the bar. Two real ones to imitate:
   > **Status:** **SHIPPED 2026-07-30** — minimos PR #55984, merge `e35b9703a`, merged 09:08:04Z. Tasks 1-4 only; 5, 7, 8 deferred (§5, and see the re-prioritised queue in validation.md §8).

   > **Status:** Research complete. Findings only — no fix designed, nothing changed.

7. **Add or update this item's `INDEX.md` row, additively.** Shape:
   `| [<item>](designs/<item>/) | <docs> | <status, quoted from the document> |`.
   Other sessions are editing `~/docs` right now: touch only your row, never reflow
   a table, never reformat a neighbour.

8. **Commit `~/docs` by pathspec.** `git -C ~/docs status --short` will show other
   sessions' staged files; a bare `git commit` or an `add -A` takes them.
   ```bash
   git -C ~/docs add designs/<item>         # a new item's folder is untracked, and a
                                            # pathspec commit cannot reach untracked paths
   git -C ~/docs diff HEAD -- INDEX.md      # confirm your row is the only change
   git -C ~/docs commit -m "<subject>" -- designs/<item> INDEX.md
   ```
   A pathspec commit ignores the rest of the index but commits the **working
   tree** — so if `INDEX.md` carries another session's in-flight edit, leave it
   out and hand the human the one-line row. The commit needs a
   `ref: <full issue URL>` trailer; if no document names the issue, **stop and
   ask**. That is a Phase 3 blocker, never something to invent or omit.

## Phase 2 — report what needs cleaning; do not clean it

Every item is a command the human runs. Emit them filled in, never as a template.

- **Raw research filed under `designs/`.** `find ~/docs/designs/<item> -type f ! -name '*.md'`
  — command output, JSON corpora, TSVs, transcripts belong in `research/<item>/`.
  First check whether a document says the copy is deliberate: a corpus kept because
  its source artifacts expire is not a misfile. Name any `.md` that is not a role
  either — roles are `design`/`spec`/`intent`, `plan`, `validation`,
  `<name>-review`, `*-evidence`.
- **Strays in the worktree.** `git -C <wt> status --short`, plus unpushed commits.
- **The session's scratchpad.** Analysis that exists only in `/tmp` dies with it, and
  a background loop outlives the window — reparented to `systemd`, closing tmux does
  not stop it. Check for scratch files newer than the documents they should have
  landed in, and run `pgrep -af "$slug"`: the adapter's own process matches,
  nothing else should.
- **The worktree and its branch.**
  ```bash
  dispatch-task.sh --cleanup <slug> --target <repo> [--target <repo> ...]
  ```
  One `--target` per directory step 0's `find` printed — the slug, never a path. Give
  its preconditions too: it **refuses** a worktree with uncommitted changes or
  commits not in the base, and `--force` discards them. If the branch was renamed,
  say that cleanup deletes `dispatch/<slug>` and leaves the renamed branch behind.

## Phase 3 — verdict

The question is **"is this work item finalized?"**, not "would closing the window
lose anything?" — a clean worktree and an idle session answer only the second.
Render all five slots; an empty one says so, none may be dropped.

```
committed:   <what you changed and committed, or "nothing">
PR state:    <ref> <STATE> <merge commit> <merged at>   ← from gh, or "no PR references found"
left undone: <each item → status line | INDEX Deferred | dropped>
for you:     <the paste-ready commands from Phase 2>
verdict:     FINALIZED, or BLOCKED: <what blocks it>
```

`BLOCKED` is the honest answer whenever a document claims something `gh`
contradicts, documents are uncommitted, commits are unpushed or carry no PR, no
issue URL exists for the `ref:` trailer, or anything is left undone with no
recorded home. It goes in the verdict slot, not as a caveat under a `yes`.

## Red flags — the verdict is not yet earned

| Thought | Reality |
|---|---|
| "The documents say it shipped, so it shipped" | Only `gh` says it shipped. Run it. |
| "It's research-only, there is no PR to check" | That claim is the thing being checked. Run `gh pr list --head` and report the empty result. |
| "Nothing is in flight, so the work item is done" | That answers "will closing lose work?", which nobody asked. |
| "Clean worktree, so it's safe to remove" | A leftover without a filled-in command, its targets and its preconditions is not reported. |
| "The blockers are listed, so `yes` is fine on top" | A `yes` with blockers under it is `BLOCKED`. |
| "I'll invent an issue URL for the trailer" | Never. Ask. |
