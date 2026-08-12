# Agents: casting the roles

A loop casts agents in four roles. They can all be the same CLI; the loop is
meaningfully better when they are not.

| Role | What it does | Wants |
| --- | --- | --- |
| **maker** | executes one card on the loop branch in the owner's project checkout | the strongest coder available |
| **judge** | reviews the run's accumulated diff at close, findings become cards | a DIFFERENT family from both the maker and whoever verified |
| **cartographer** | compares the spec to the code, emits the next cards | strong reasoning, large context |
| **critic** | looks at the running product, emits improvement cards | eyes: it must see screens |

One rule is not negotiable: **the judge comes from a different model family
than whoever made and verified the work**. The skill says why: another family
pays for judgment gaps, the ones you do not know where to look for. Everything
else is taste and budget.

## Casting from what is installed

Detect the agent CLIs actually present (claude, codex, gemini, hermes, a local
model runtime) rather than asking the owner to recite them. Then:

- **Two or more families**: the best coder makes, another family judges. A
  third, if present, makes a good cartographer: large context matters more
  there than coding strength.
- **One family only**: run without a judge rather than with a same-family one,
  and say so in the report. A rubber-stamp review is worse than none, it
  creates false confidence.
- **A local model available**: the cheapest extended run is a local maker with a
  frontier judge and cartographer. Fewer greens per hour at a fraction of the
  cost, and the judge catches what the weaker maker misses.

## Escalation

A card that failed once is retried by a DIFFERENT model, never the same one
again: same model, same blind spot, same failure. On the origin project this
rescued cards that had failed twice. Keep one strong model in reserve for
exactly this.

## Operational notes paid for in real runs

- The Codex CLI rejects arguments that are not valid UTF-8. One truncated
  multi-byte character pasted into a card once hard-failed every cycle that
  touched it. If you assemble prompts from file content, guarantee their
  encoding first.
- Give a maker a time budget it can actually finish a card within. Too short
  converts good work into false reds, and the failure reads as the card's
  fault.
- Provider overload, rate limits and quota estimates are infrastructure,
  never the card's fault. The rules, each from a failed run window, are in
  `doctrine.md` §8.
