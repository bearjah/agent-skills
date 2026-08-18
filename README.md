# agent-skills

Reusable workflows for Claude Code and Codex.

## Included

- `promptify`: turn a rough request into an executable prompt.
- `finalize-work`: verify and hand off dispatched work.
- `git-commit`: create focused commits with useful history.
- `dispatch`: open an isolated worktree session in tmux or Herdr.

## Install

Run the installer for your agent:

```bash
adapters/claude/dispatch/install.sh
adapters/codex/dispatch/install.sh
```

Adapter-specific usage is documented in each adapter directory.

Set `AGENT_DOCS_ROOT` to move durable briefs, designs, reviews, and research from
the default `~/docs` root.
