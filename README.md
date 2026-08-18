# agent-skills

Reusable agent workflows, organized so their instructions can be shared across
LLM engines without treating one engine as the source of truth.

## Layout

```
skills/            Engine-neutral workflow instructions
core/              Shared engine-neutral implementation helpers
adapters/<engine>/ Engine-specific commands, installers, and CLI integration
```

`skills/` and `core/` contain portable behavior. An adapter only supplies the
engine's discovery path, command format, CLI integration, and worktree root.
This repository currently includes a Claude adapter; adding another engine
should not require changing a skill unless that engine lacks a capability the
skill relies on.

## Included workflows

| Workflow | Purpose |
| --- | --- |
| `skills/promptify` | Rewrite an underspecified request into an executable prompt, then wait for approval. |
| `skills/finalize-work` | Reconcile dispatched work, its evidence, documentation, and cleanup instructions before closing it. |
| `adapters/claude/dispatch` | Claude Code command and CLI integration for dispatching isolated worktree sessions. |

## Engine adapters

Each adapter owns its own installation instructions. The Claude adapter links
the portable skills into `~/.claude/skills` and supplies Claude-specific slash
commands and CLI behavior. Other engines can consume a `SKILL.md` directly or
add an adapter under `adapters/<engine>/`.

## Worktree locations

Dispatch worktrees are kept out of source checkouts. Each adapter chooses its
own default root and may be overridden with `DISPATCH_WORKTREE_ROOT`:

| Adapter | Default layout |
| --- | --- |
| Claude Code | `~/.claude/worktrees/<repo>/<slug>` |
| Generic core | `~/.agent-skills/worktrees/<repo>/<slug>` |

A Codex adapter should use `~/.codex/worktrees/<repo>/<slug>` while reusing the
same `core/dispatch` lifecycle.
