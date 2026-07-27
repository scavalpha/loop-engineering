# Agents: casting the roles

The loop uses agents in four distinct roles. They can all be the same CLI, but
the loop is meaningfully better when they are not.

| Role | What it does | Wants |
| --- | --- | --- |
| **maker** | executes one card in a throwaway worktree | strong coding model, a terminal |
| **checker** | reviews each green diff, emits fix cards | a DIFFERENT family than the maker |
| **cartographer** | reads your spec vs the code, emits the next cards | strong reasoning, large context |
| **critic** | looks at the running product, emits improvement cards | vision capable (screenshots) |

The one rule that is not negotiable: **maker and checker must come from
different model families**. A model reviewing its own family rubber-stamps its
own idiom and finds nothing. Everything else is taste and budget.

## The three supported CLIs

All three are first-class. The law routes by model family automatically:
a model named `claude-*`, `*opus*`, `*sonnet*`, `*haiku*` goes to the Claude
CLI, `codex`, `gpt-*`, `o1-*`, `o3-*`, `o4-*` go to Codex, anything else falls
back to the configured kind (Hermes by default).

### Hermes

The original maker of this law, and still the most protected one: it is the
only agent with a loop-scoped profile (`setup-hermes-profile.sh`) that adds

- a **write-boundary hook**: file writes outside the worktree are blocked at
  the tool level, on top of the worktree isolation itself,
- **provider fallback**: a dead primary provider does not kill the night,
- **scoped memory**: the loop's memory does not leak into your personal one.

It also supports local models (MLX, Ollama) through the same path, with
`mlx-keeper.sh` keeping a local model warm. That is the cheapest way to run a
long night, at the cost of a weaker maker.

```bash
LOOP_MAKER_KIND=hermes
LOOP_MAKER=<model-name>          # whatever your Hermes profile serves
```

### Claude Code

```bash
LOOP_MAKER_KIND=claude
LOOP_MAKER=claude-opus-5         # or any current model id
LOOP_CLAUDE_EFFORT=medium        # effort knob, when supported
```

Runs non-interactive with permissions bypassed INSIDE the worktree. Read the
containment note in `stack-contract.md` before changing that.

### Codex

```bash
LOOP_MAKER_KIND=codex
LOOP_MAKER=gpt-5-codex           # or your available model
LOOP_LOT_CHAIR=codex             # commonly used as the checker
```

One hard constraint: the Codex CLI rejects arguments that are not valid UTF-8.
The law sanitizes every prompt before invoking it, because a single truncated
multi-byte character pasted into a card once hard-failed every cycle that
touched that card.

## Recommended castings

**You have all three** (the richest case):

```bash
LOOP_MAKER_KIND=claude     LOOP_MAKER=claude-opus-5      # maker: the best coder you have
LOOP_LOT_CHAIR=codex                                     # checker: other family, mandatory
LOOP_CARTO_MODEL=<strong reasoning model>                # cartographer
LOOP_CRITIC_MODEL=<vision capable model>                 # product critic
LOOP_ESCALATION_MAKER=<different strong model>           # retries after a red
```

Escalation matters more than it looks: a card that failed once is retried by a
DIFFERENT model, which breaks the "same model, same blind spot, same failure"
loop. In production this rescued cards that had failed twice.

**Budget night**: Hermes with a local model as maker, a frontier model only as
checker and cartographer. Fewer greens per hour, a fraction of the cost.

**Single CLI available**: run without a checker rather than with a same-family
one, and say so in the report. A rubber-stamp review is worse than none: it
creates false confidence.

## Cost and quota reality

A frontier maker on a 7-hour night is expensive. The law defends the window:

- a proactive quota gate pauses BEFORE starting a cycle it cannot finish,
- but it never holds the night hostage on a frozen metric (if the reading does
  not move across two probes, it resumes: a stalled sensor or a weekly quota
  that will not refill are both reasons to continue, not to wait),
- rate limits and overloads pause and retry the same card, never blame it.

Set `LOOP_MAKER_TIMEOUT` to something your model can actually finish a card
within. Too short converts good work into false reds.
