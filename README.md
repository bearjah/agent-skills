# agent-skills

Reusable workflows for Claude Code and Codex.

## Included

- `promptify`: turn a rough request into an executable prompt.
- `dispatch`: open an isolated worktree session in tmux or Herdr.
- Claude home setup: global instructions, model routing, and the agents they
  use, for a new machine.

## Install

Clone the repository, then run the installer for each part you want. The
installers link files into your agent's home directory, so keep the clone where
it is afterwards.

```bash
git clone https://github.com/bearjah/agent-skills.git ~/agent-skills
cd ~/agent-skills

adapters/claude/home/install.sh        # global instructions, agents, skills plugin
adapters/claude/dispatch/install.sh    # the /dispatch command
adapters/codex/dispatch/install.sh     # promptify and dispatch for Codex
```

### Setting up Claude Code on a new machine

1. Install Claude Code and log in.
2. Install `jq`, which the home installer uses to update `settings.json`.
3. Clone this repository and run `adapters/claude/home/install.sh`. If the
   machine already has its own `~/.claude/CLAUDE.md` or agents and you want
   this setup instead, add `--replace`: the old files are moved to a backup
   folder first.
4. Start Claude Code. If the `agent-skills:*` skills are not listed, run
   `/plugin install agent-skills@addy-agent-skills` once.
5. Choose your own model and permission mode with `/config`; settings are not
   shared between machines.

Details for each part:

- [Claude home setup](adapters/claude/home/README.md)
- [Claude dispatch](adapters/claude/dispatch/README.md)
- [Codex dispatch](adapters/codex/dispatch/README.md)

Set `AGENT_DOCS_ROOT` to move durable briefs, designs, reviews, and research from
the default `~/docs` root.
