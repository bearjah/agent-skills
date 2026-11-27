# Claude home setup

The global setup for Claude Code on a machine: how work is planned, which
skills are used, and which model does what.

## What it contains

- `CLAUDE.md`: instructions loaded into every Claude Code session.
  - **Engineering workflow**: which skill to use for a bug, a feature, or
    specialised work, and how much process a task deserves.
  - **Model routing**: which agent and model each kind of work goes to.
  - **Working agreement**: the scope, Definition of Done, spec and plan are
    approved up front; after that the agent works alone, merges its own pull
    requests where the repository allows, and notifies when the work is ready.
- `agents/`: the agents the routing table sends work to.
  - `scout`: read-only search and summarising.
  - `runner`: runs tests, builds and linters and reports failures.
  - `planner`: writes implementation plans for complex work.
  - `implementer`: builds one already-specified task.

The skills named in `CLAUDE.md` (`agent-skills:spec-driven-development` and the
rest) come from the [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills)
plugin, which the installer enables.

## Install

```bash
./install.sh
```

Requires `jq`. The installer:

- links `CLAUDE.md` to `~/.claude/CLAUDE.md` and each agent to `~/.claude/agents/`;
- adds the plugin and its marketplace to `~/.claude/settings.json`, keeping
  every setting already there.

It changes nothing if `~/.claude/CLAUDE.md` or one of the four agents already
exists with different content. Other agents in `~/.claude/agents/` are left
alone. Running it twice is safe.

### Replacing an existing setup

```bash
./install.sh --replace
```

Use this on a machine whose current setup you no longer want. Each file that
would be replaced is first moved to `~/.claude/backups/home-setup-<date>-<time>/`,
and the installer prints where. Only `CLAUDE.md` and the four agents are
replaced: other agents, skills and every existing setting stay as they are. To
go back, move the backed-up files over the links.

Start Claude Code afterwards. If the plugin's skills are not listed, run
`/plugin install agent-skills@addy-agent-skills` once.

## What it leaves to you

Settings are personal, so they are not shared: model, theme, notifications and
the permission mode are set on each machine. The working agreement assumes the
agent is rarely stopped by permission prompts; choose the permission mode that
suits the machine with `/config`.

## Changing the setup

The installed files are links into this repository, so an edit made on any
machine is a change here: commit it, push, and pull on the others.
