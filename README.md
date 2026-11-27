# agent-skills

Reusable workflows for Claude Code and Codex.

## Included

- `promptify`: turn a rough request into an executable prompt.
- `dispatch`: open an isolated worktree session in tmux or Herdr.
- Claude home setup: global instructions, model routing, and the agents they
  use, for a new machine.

## Install

Run the installer for your agent:

```bash
adapters/claude/home/install.sh        # global instructions, agents, skills plugin
adapters/claude/dispatch/install.sh    # the /dispatch command
adapters/codex/dispatch/install.sh
```

Adapter-specific usage is documented in each adapter directory.

Set `AGENT_DOCS_ROOT` to move durable briefs, designs, reviews, and research from
the default `~/docs` root.
