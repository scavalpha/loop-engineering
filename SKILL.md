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

**How often.** At the start of every run, before touching a card. It costs a
few minutes and it decides whether the next hours are worth anything. If you
run several times a day and that feels heavy, make it every third run at
worst, never less.

Do it immediately, whatever the schedule says, when any of these appear:

- **two cycles in a row that changed nothing.** The queue is describing work
  that is already done. Stop and look, do not pick a third card.
- **a card failing for a reason you have seen before.** Something upstream is
  wrong: a stale spec, a rule that changed, a check that lies.
- **the queue growing while nothing ships.** Reviewers and product passes
  generate cards faster than they get consumed, so a queue only grows until
  someone prunes it.
- **coming back after a break**, or picking up a project someone else drove.
  You have no idea what happened in between, and the cards will not tell you.

The drift is continuous, not occasional: every run adds cards from reviews and
product passes, while the code moves under them. On the project this comes
from, nobody had ever pruned, and by the time anyone looked, 109 of 128 cards
described work already done and 4 would have actively broken the product if
executed.

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

**Verifying with your own command instead of the project's.** A generic test
runner invoked directly can skip the setup the project's own command performs,
and then everything fails for a reason that has nothing to do with the work.
Run what the project runs. On the run this comes from, a bare runner reported
thirty-three files failing on untouched code; the project's own command
reported all of them passing, and it was right.

**Reading one queue while working in another tree.** If the work happens on a
branch or a worktree, the units of work you pick must come from that same
place. On the run this comes from, the queue had been pruned from 128 cards to
18 on one branch while the working tree still carried all 139: every decision
about what mattered next was made from a list that was not the one on disk.

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

**Believing a report about anything outside the diff.** Verifying the work
does not verify the account of it. A maker that says it filed a follow-up,
killed what it started, or undid its own scaffolding is making a claim nothing
in your gates touches, and it will read as done. Look at the artifact, or do
not count it. Better: do not ask a maker to keep the memory at all. It reports
what it found, you file it. A side task nobody checks is a side task nobody
does.

**Regressions losing to features.** A defect found in shipped work outranks
anything new. Fix forward: the code passed its gates, refine it rather than
reverting.

**Merging your own work.** Accumulate results on a branch, verify
independently, report what is mergeable. The owner merges.

**Running without being asked.** Setting up and running are two decisions. The
second belongs to the owner, every time, and a run left unsupervised for hours
is how a small anomaly becomes a wasted night.

## Closing a cycle: what you believe against what is there

Every failure in the list above was caught the same way, and never by thinking
harder. Something was checked against reality: a directory listed, an error
read, a file counted, a fix reverted to see the test go red. The gap is
never *reasoning*, it is always *belief that was never confronted*.

So close every cycle by confronting yours. These are questions to answer with
evidence, not a script to run, and a "no" is not a failure of the cycle, it is
the next card:

- **Does the queue I chose from match the tree I worked in?** Same branch, same
  files. If two lists exist, every priority decision was taken on the wrong one.
- **Did everything I said I did actually happen?** Not the code, the rest: a
  follow-up filed, a process killed, scaffolding undone. Look at the artifact.
- **Did this cycle change the product, or only the story about it?** A cycle
  with no source diff is a cycle that discovered the work was already done. Say
  so and prune, do not pick a second card and hope.
- **Are the gates green on the whole, not on my files?** Ten green cards can
  compose into a broken product.
- **Did anything I started outlive me?**
- **Did this card fail for a reason I have already seen?** Then the problem is
  upstream: a stale spec, a rule that changed, a check that lies. Fix that, not
  the card.
- **What did I learn that would have saved this cycle?** Write it down now, as
  a card if it is about the product, as a line here if it is about the craft. A
  lesson that survives only in a session is not a lesson.

That last question is the whole machine. A loop gets better because each cycle
ends with less that can go wrong, not because a bigger model runs it. And the
learning has to compound as **fewer things to check, not more**: the loop this
comes from carried six thousand lines of guardrails written for a weak executor,
and deleting them made it better. When you add a rule, look for the two it makes
unnecessary.

**What no amount of this will do.** A loop verifies what it can observe: that
it builds, that the tests pass, that a card's condition holds, that it did what
it claimed. It cannot tell you the design is wise or the product is right. That
part stays yours, and a loop that pretends otherwise is lying to you politely.

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