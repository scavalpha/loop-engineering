# loop-engineering

A skill for coding agents: set a goal on a project and pursue it autonomously,
one verifiable unit of work at a time, until the goal's condition actually
holds.

It contains no scripts. An agent capable of building software is capable of
building its own harness and judging what it needs to accomplish a task. What
it cannot derive is what has already failed on real projects, and that is what
this skill carries.

## Install

Clone the public repository directly into your agent's skills directory. No
`~/dev` folder is required.

### Claude Code

```sh
mkdir -p ~/.claude/skills
git clone https://github.com/scavalpha/loop-engineering.git \
  ~/.claude/skills/loop-engineering
```

### Codex

```sh
mkdir -p ~/.codex/skills
git clone https://github.com/scavalpha/loop-engineering.git \
  ~/.codex/skills/loop-engineering
```

Recent Codex CLI versions load the Agent Skills format from
`~/.codex/skills/loop-engineering`. On older versions, add a line to the
project's `AGENTS.md` pointing at the cloned `SKILL.md`.

### Claude Code and Codex from one clone

To keep one copy shared by both agents:

```sh
mkdir -p ~/.local/share/agent-skills ~/.claude/skills ~/.codex/skills
git clone https://github.com/scavalpha/loop-engineering.git \
  ~/.local/share/agent-skills/loop-engineering
ln -s ~/.local/share/agent-skills/loop-engineering \
  ~/.claude/skills/loop-engineering
ln -s ~/.local/share/agent-skills/loop-engineering \
  ~/.codex/skills/loop-engineering
```

These commands intentionally stop if a skill already exists at either target;
inspect and remove or rename the existing copy before replacing it.

### Update

Run `git pull --ff-only` in the directory you cloned. For example:

```sh
git -C ~/.codex/skills/loop-engineering pull --ff-only
```

Hermes or any other compatible agent can use the same repository by pointing
its skill loader at `SKILL.md`.

## Requirements

- A reasoning agent with shell and git access. Nothing else is imposed: the
  agent builds the harness that fits the project.
- Ideally a second model family installed, because the closure judge is
  defined relationally: its family differs from the maker's and from the
  verifier's. If only one family is available, the skill requires the run
  report to say so instead of implying an independent review happened.

## Use

Tell your agent what you want and let it work:

    "Start a loop on this project: get the checkout flow working end to end."

Before the autonomous window begins, it resolves anything material it cannot
observe, writes the spec and first cards with you when needed, and proves the
base is sound. During the run it works directly in the project folder you
provided, on the current branch or a local branch. It does not create a clone
or worktree unless you explicitly request one. It decides how to verify the
work and what tooling the project needs.

## What it gives the agent

- The shape of a goal worth pursuing autonomously: a condition a machine can
  settle, not one a model can talk itself into.
- The failures that cost real nights: believing instead of running, half
  applied work, per-unit checks missing assembly breakage, a saturated machine
  lying, infrastructure blamed on the card, orphan processes, frozen
  implementations mistaken for tests, self-review, regressions losing to
  features, merging its own work, running unasked.
- Detail on demand in `references/`: doctrine with the incident behind each
  law, card format, agent casting, non-code domains, supervision.

## Where it comes from

Distilled from months of overnight runs on production projects, and from a
long argument about how much of that machinery was ever necessary. Most of it
was scaffolding for a weak executor. What survived is here.

## License

MIT, see LICENSE.
