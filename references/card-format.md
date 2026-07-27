# Cards: units of work that cannot lie

A card is a markdown file stating WHAT must be true when the work is done, in
the product's language. It does not say how to check that: you read the
project and decide, better than any frozen instruction could.

```markdown
# Search the client directory from the documents screen

VALUE: P0

USE CASE:
A user types part of a client name and finds that client's files, without
knowing any reference number.

DONE WHEN:
- Typing three letters shows matching clients, searched server-side, not
  filtered in the browser
- Selecting one shows only that client's files, and going back restores the
  full list
- Two different companies sharing a name stay distinct
- The rule that a file is only visible within the user's perimeter still holds
```

That is the whole format. A title, a priority, what it is for, and what must
be true at the end.

## Writing DONE WHEN

Write it as the acceptance test a demanding person would run: name who acts,
what they see, what changes. Then two habits that save rework:

**List the rules that must SURVIVE.** Without it, work that satisfies a card
by deleting an existing behaviour looks green. "The perimeter rule still
holds", "the frozen circuit is not recalculated", "the mandatory document
stays blocking".

**Say which side must move when something conflicts.** If a test fails against
a rule, state whether the test is stale or the code is wrong. Left implicit,
the cheapest fix wins, and the cheapest fix is usually deleting the rule.

## Sizing

One card is one concern, provable in one sitting. A card that cannot be
finished in a single stretch of work should be several, ordered by dependency.

Priority is a hint for what to do next, nothing more: P0 blocks use, P1 is the
product's core, P2 and P3 are refinement. A defect found in shipped work
outranks anything new.

## Recording a check for the future

Most of the time you verify a card by reading, running and testing, then move
on. But when a defect has cost real time, write down what would have caught
it, and keep verifying it from then on.

That check must describe BEHAVIOUR, not implementation. Asserting that a
constant exists breaks the day the product rightly improves: on the project
this doctrine came from, 22 of 166 recorded checks had silently gone false,
mostly by freezing an implementation that later changed for the better.

And a check only proves something if it fails today. One that already passes
before the work exists proves nothing, and will happily declare a card done
with nothing built. Confirm it fails first.

## Cards born from findings

When a reviewer finds defects in shipped work, they become a card at top
priority, and nothing is reverted: the code passed its checks, so refine it
forward. Give that card the same treatment as any other, stating what must be
true rather than just "fix these three things". Otherwise the only thing
verifying it is that the project still compiles, which was already true
before: measured on the origin project, every single generated fix card had
that weakness.

## Cards that describe an observed defect

A repair card is special: it describes something that WAS seen. If everything
it asks for already appears satisfied, the honest conclusion is that its
criteria are too weak, never that the defect fixed itself. Sharpen them, or
verify by hand and report what you found.
