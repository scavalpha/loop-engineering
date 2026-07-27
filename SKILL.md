---
name: loop-engineering
description: Set a goal on a local project and pursue it autonomously, one verifiable unit of work at a time, until the goal's condition actually holds. You decide how: how to isolate your work, how to verify it, what to build yourself. This skill gives you the goal shape and the failures that cost real nights, nothing else. Works on code and beyond (manuscripts, docs, datasets) wherever work can be verified. Use for overnight loops, autonomous development, self-improving build loops. Triggers include "loop engineering", "overnight loop", "autonomous loop", "boucle autonome", "run cards".
---

# Loop Engineering

Pursue a goal on a project, autonomously, until it genuinely holds.

You know how to do this. Build your own harness: decide how to isolate your
work, how to verify it, what to keep between sessions, what tooling you need.
This document does not tell you which commands to run. It tells you the shape
of the goal, and the ways this has failed on real projects, because those you
cannot derive.

## The shape

A goal worth pursuing autonomously has a condition that a machine can settle,
not one you can talk yourself into:

> *until the project builds, the whole test suite passes, and nothing in the
> spec is left unimplemented*

not

> *until the feature works well*

The unit of work is a card: a file stating what must be true when it is done,
in the product's language. The spec (`docs/domain-rules.md`) says what the
product is; cards say what to do next. Both are files in git, because that is
what survives you.

## Start by looking at the whole thing

Do not open the first card and start working. Look at where the project stands
and what is still queued, together, and decide what deserves the next hours.

That review answers four questions:

- **What does the spec still not cover?** Compare it to what the code actually
  does, not to what earlier cards claimed.
- **Which queued cards are already satisfied?** Work gets done under other
  names, by side effects, by earlier fixes. Retire them now rather than
  spending a cycle each discovering it.
- **Which have gone stale?** A card written against an implementation that has
  since changed for the better describes a world that no longer exists.
  Rewrite it around the behaviour, or drop it.
- **What actually matters next?** A queue is not a plan. Order it by what the
  product needs, and say what you are deliberately not doing.

Do this at the start of a run, and again whenever the queue stops matching the
project, which happens faster than anyone expects.

**Why it matters more than it sounds.** On the project this comes from, the
queue held 128 cards and the review only ever ran when it emptied, so it never
ran. Two consecutive runs then spent their whole window on cards whose work had
already been done: thirty-six minutes of a strong model, zero lines changed.
Nothing was broken; nobody had looked.

The same review keeps the memory honest. Recorded checks rot: 22 of 166 had
silently gone false, most of them freezing an implementation the product had
rightly improved. A check that fails because the product got better is not a
regression, it is a check to delete.

## What has actually gone wrong

Every item below cost a night, a lost day, or shipped a defect.

**Believing instead of running.** Nobody can reason that a project compiles.
The single most expensive failure mode is accepting work because it looks
done. Execute the build, execute the tests, read the output.

**Half-applied work.** A card that ends neither committed nor reverted rots
the codebase silently. Make outcomes atomic and make failure cheap: work
somewhere disposable, keep the diff of what failed, never leave debris.

**Per-unit checks missing assembly breakage.** Ten cards each verified green,
product broken: they interact. Verify the whole thing regularly, and always
before merging.

**A saturated machine lying to you.** A backend killed by memory pressure
produces failures indistinguishable from real regressions. Check the machine
before believing a red that contradicts a recent green.

**Blaming the card for infrastructure.** Provider overload, dropped network,
exhausted quota: pause and retry the same card. Never escalate it, never mark
it failed, and never wait on a metric that has stopped moving.

**Orphans.** Processes you spawn outlive you: a maker whose orchestrator is
gone keeps writing with nobody left to judge it. Kill what you started.

**Freezing an implementation and calling it a test.** Asserting that a
constant exists breaks the day the product rightly improves. Verify behaviour.
On the project this came from, 22 of 166 such checks had silently gone false.

**Checks that were never discriminating.** A check that already passes before
the work exists proves nothing, and it will mark a card done with nothing
built. Before trusting one, confirm it fails today.

**Self-review.** A reviewer sharing the maker's idiom finds nothing. Get
checked by a different model family, or state plainly that you were not.

**Regressions losing to features.** A defect found in shipped work outranks
anything new. Fix forward: the code passed its gates, refine it rather than
reverting.

**Merging your own work.** Accumulate results on a branch, verify
independently, report what is mergeable. The owner merges.

**Running without being asked.** Setting up and running are two decisions. The
second belongs to the owner, every time, and a run left unsupervised for hours
is how a small anomaly becomes a wasted night.

## Beyond code

Nothing here assumes code. Replace building and testing with whatever settles
truth in your domain and the doctrine holds: a novelist's cards are chapters,
the spec is the story bible, the checks are continuity against established
facts and prose linters.

Before starting anywhere, answer one question: **what can mechanically prove
this work is done?** A vague answer means you would be asking a model to grade
itself, which is the failure this whole doctrine exists to prevent.

## References

Read these when you want the detail behind a rule, not before starting.

- `references/doctrine.md` — each law with the incident that created it
- `references/card-format.md` — units of work that cannot lie
- `references/running-a-loop.md` — one worked way of pursuing a goal
- `references/agents.md` — who does the work, who checks it
- `references/getting-started.md` — from a spec to a working loop
- `references/what-travels.md` — knowledge vs what a project learns about itself
- `references/beyond-code.md` — books, documents, datasets