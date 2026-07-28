# From a spec to a working loop

You need two things before starting: what the product must be, and a first
unit of work. Everything else you derive.

## The spec

`docs/domain-rules.md` holds what the product IS: use cases and rules in its
own language. Write rules a machine could violate.

```markdown
# Shopping app, rules

## Use cases
- UC1 Browse: a visitor sees a catalog, filters by category and price
- UC2 Cart: items survive an app restart
- UC3 Checkout: a signed-in customer pays and gets a confirmation

## Rules
- Prices are stored in cents, never floats
- The cart is per-device until sign-in, then merged into the account
- Stock is checked at checkout, never only at add-to-cart
- An order is immutable once paid: changes create a new order
```

Precision here pays for itself: this is what tells you whether a unit of work
is finished, and what the next one should be.

## The first units of work

Two or three cards, each stating what must be true when it is done. Keep them
small and unambiguous for the first run: you are proving the harness works on
this project, not shipping the product.

## Before running anything

Prove the base is sound: build it, test it, on an untouched tree. If it is
already red, stop and say so, never build on it silently: every verdict
afterwards would be meaningless. A red base is not a dead end, it is a
different first goal. First reproduce and classify each baseline failure.
With the owner's explicit consent, card the reproducible product defects;
record infrastructure and flaky failures separately, they are not product
debt; and never admit a new regression against the observed baseline.

Name, before launch, every observation the goal requires that you cannot
perform: a screen you cannot see, a device you cannot drive. A missing
capability narrows the agreed goal or blocks the run, it never silently
weakens what DONE means.

## What you ask the owner

Only what you cannot observe. Detect the rest yourself: which agent CLIs exist,
what the stack is, whether tests already run, whether a spec exists somewhere.

Worth asking:

- what the product must do, if there is no spec yet
- who should do the work and who should review it (different families)
- how long the first run should last, and their budget
- what must be running for tests to pass (a database, a service)
- what they want prioritised right now

Then work. Do not launch anything at setup time: setting up and running are
two decisions, and the second belongs to them.

## Domains without a compiler

Mobile, CLI, library, prose, data: same doctrine. What changes is what settles
truth. If your domain has no runtime check at all, say so plainly rather than
pretending unit tests prove the product works, and lean harder on whatever
does verify: a simulator run, a schema validation, a linter, a consistency
script you write yourself.
