# loop-engineering

A skill for coding agents: set a goal on a project and pursue it autonomously,
one verifiable unit of work at a time, until the goal's condition actually
holds.

It contains no scripts. An agent capable of building software is capable of
building its own harness and judging what it needs to accomplish a task. What
it cannot derive is what has already failed on real projects, and that is what
this skill carries.

## Install

Claude Code:

    git clone <this-repo> ~/dev/loop-engineering
    ln -s ~/dev/loop-engineering ~/.claude/skills/loop-engineering

Codex: recent CLI versions load the same Agent Skills format from
`~/.codex/skills/loop-engineering`. Otherwise add a line to `AGENTS.md`
pointing at `SKILL.md`.
Hermes or any other agent: point it at `SKILL.md`.

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

It will ask what it cannot observe, write the spec and the first cards with
you, prove the base is sound, and then work. It decides how to isolate its
work, how to verify it, and what tooling it needs.

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
