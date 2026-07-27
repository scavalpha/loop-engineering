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
- `references/card-format.md` — cards and checks that cannot lie
- `references/agents.md` — casting maker, reviewer, cartographer, critic
- `references/getting-started.md` — from a spec document to a running loop
- `references/generic-vs-project.md` — what travels vs what is learned here
- `references/beyond-code.md` — books, docs, datasets
- `references/supervision.md` — watching a run, failure classes, closing
- `references/native-mode.md` — one worked protocol, if you want a starting point
