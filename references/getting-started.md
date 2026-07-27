# From a spec document to a running loop

You do not need to write cards by hand to start. The loop has a CARTOGRAPHER:
when the queue is empty, it compares your spec to the code that actually
exists and emits the next most useful cards, with a coverage matrix telling
you which requirements are done, partial, or untouched.

So the real starting material is your spec, in `docs/domain-rules.md`.

## The three files that drive everything

| File | What it is | Who reads it |
| --- | --- | --- |
| `docs/domain-rules.md` | your spec: business rules, use cases, constraints | cartographer, every maker prompt |
| `loop/stack.sh` | how to build and test THIS project | the whole law |
| `loop/NIGHT-BRIEF.md` | what YOU want prioritized right now (optional) | cartographer, highest weight |

Nothing else is mandatory. Cards appear on their own from the first two.

## Worked example: a mobile shopping app

Say you are building a shopping app in React Native, with a Node API.

**1. Write the spec** in `docs/domain-rules.md`. Write it as rules and use
cases, in your product's language, not as tasks:

```markdown
# Shopping app, business rules

## Use cases
- UC1 Browse: a visitor sees a product catalog, filters by category and price
- UC2 Cart: a visitor adds and removes items, the cart survives app restart
- UC3 Checkout: a signed-in customer pays and receives an order confirmation
- UC4 Orders: a customer sees past orders and their status

## Rules
- Prices are stored in cents, never floats, and displayed in the user locale
- The cart is per-device until sign-in, then merged into the account cart
- Stock is checked at checkout, never only at add-to-cart
- An order is immutable once paid: changes create a new order
```

Precision here pays for itself: every maker prompt carries these rules, and
the cartographer measures coverage against them.

**2. Fill `loop/stack.sh`** with the truth of your stack:

```bash
STACK_NAME="shopping-app"
ARCH_PROFILE="mobile"                 # web-fullstack | api-only | mobile | lib | cli
BACK_DIR="api"
FRONT_DIR="app"
GATE_FRONT_CMD='cd app && npx tsc --noEmit && npx jest --ci'
GATE_BACK_CMD='cd api && npm test'
STACK_INSTALL_CMD='cd app && npm ci && cd ../api && npm ci'
STACK_INSTALL_SENTINEL="app/node_modules"
STACK_BRIEF='React Native 0.7x + Expo in app/, Node 22 + Fastify + Prisma in
api/. Money in cents everywhere. Tests: jest both sides, API tests use a
disposable sqlite file, never the dev database.'
```

`ARCH_PROFILE` matters: it tells the law whether this project even has a web
front, so screen-oriented mechanisms stay off when they make no sense.

**3. Seed two or three cards yourself anyway.** The cartographer is good at
continuing, less at the very first step on an empty repo. Two small,
over-probed cards are enough to prove the harness works on your machine
(read `card-format.md` first). After that, let the cartographer fill the
queue.

**4. First run**, short and supervised:

```bash
bash loop/probe-lint.sh loop/tasks/*.md   # zero findings expected
bash loop/verify.sh                       # gates must be green on a clean tree
bash loop/loop.sh 1h                      # then watch loop/logs/run-*.log
```

## Steering it later

- **Change priorities**: write `loop/NIGHT-BRIEF.md` in plain language ("focus
  on checkout, ignore the profile screen for now"). It outweighs everything
  else in the cartographer's prompt.
- **Add a rule mid-project**: edit `docs/domain-rules.md`. The next cards will
  respect it, and the coverage matrix will show the gap it opened.
- **Disagree with a card**: delete it from `loop/tasks/`, or rewrite it. Cards
  are files, nothing is sacred.

## Stacks other than web

The law is stack-agnostic: it only knows the commands your contract gives it.
Mobile, CLI, library, API-only all work, with two caveats:

- **The runtime gate is what makes a loop trustworthy.** For web it is
  Playwright; for mobile, wire `E2E_CMD` to Detox, Maestro or your simulator
  runner. Without any runtime gate you still get build plus unit tests, which
  is decent, but assembly regressions will reach you later than they should.
- **Set `ARCH_PROFILE` correctly**, otherwise screen-oriented helpers try to
  scaffold pages a mobile app does not have.

If your stack has no headless runtime test at all, say so in `STACK_BRIEF` and
lean harder on unit-level probes.
