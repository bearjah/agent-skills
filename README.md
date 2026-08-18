# agent-skills

Reusable agent workflows, organized so their instructions can be shared across
LLM engines without treating one engine as the source of truth.

## Layout

```
skills/            Engine-neutral workflow instructions
adapters/<engine>/ Engine-specific commands, installers, and CLI integration
```

`skills/` contains the portable behavior. An adapter only supplies the
engine's discovery path, command format, or CLI integration. This repository
currently includes a Claude adapter; adding another engine should not require
changing a skill unless that engine lacks a capability the skill relies on.

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
