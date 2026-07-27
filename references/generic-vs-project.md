# The two halves: the law travels, the learning stays

A loop has two halves, and confusing them is what makes a loop unportable or
a project amnesiac.

- **The LAW** is generic. It knows how to pick a card, drive an agent, judge
  with gates, commit or reset, classify an infra failure, cap a fix chain.
  It knows nothing about your product. It comes from the skill, it is
  overwritten on every sync, and you never edit it in place.
- **The LEARNING** is yours. It is everything the loop discovered about YOUR
  project: your contract, your cards, your taste rules, your hints, your
  project-specific assertions. It is never overwritten, and it is the reason
  a loop gets better on a project over time instead of restarting from zero
  every night.

A loop that only has the law is competent but naive. A loop that only has
learning is not a loop, it is a pile of notes.

## Where each thing lives

```
loop/
  *.sh                    LAW      driver, cycle, gates, critic, distiller...
  hooks/                  LAW      write-boundary hook, guardrails
  shims/                  LAW      restricted tool shims
  carto-lenses.md         LAW      how the cartographer looks at a codebase
  tests/harness-test.sh   LAW      assertions guarding the law itself
  LAW-VERSION             LAW      which law you are running

  stack.sh                PROJECT  your contract: dirs, gates, casting, brief
  tasks/                  PROJECT  your cards
  skills/                 PROJECT  taste rules the loop learned HERE
  hints.d/                BOTH     generic hints ship, learned ones accumulate
  tests/project-test.sh   PROJECT  assertions about YOUR conventions
  state/ wip/ logs/       PROJECT  run state, never shared, gitignored

docs/domain-rules.md      PROJECT  your spec, read by the cartographer
```

`sync-law.sh` rewrites the LAW column and never touches the PROJECT column.
That is the whole contract between the skill and your repo.

## Why a project grows its own assertions

The law's harness proves the law is sound: probes cannot lie, a repair card
cannot self-complete, an infra failure never blames a card. Those assertions
are true everywhere, so they travel.

But every project also acquires rules that only make sense there:

- "no component may import the ORM directly, it goes through a repository"
- "every endpoint returning money uses the Money type, never a float"
- "the story bible is the only place a character may be introduced"
- "no test may hit the network"

These deserve to be enforced mechanically, exactly like the law's own rules,
and the honest place for them is `loop/tests/project-test.sh`: a file the law
never overwrites, that you grow as the loop teaches you what breaks here.

Seed it the first time you catch a mistake twice. That is the signal: a class
of error that recurs is a missing assertion, not a careless agent.

```bash
# loop/tests/project-test.sh, yours, never synced
fail=0
check(){ printf '%-52s' "$1"; shift; if "$@" >/dev/null 2>&1; then echo ok; else echo FAIL; fail=1; fi; }

check "no direct ORM import in components" \
  bash -c '! rg -q "from .*orm" src/components'
check "money never a float" \
  bash -c '! rg -qE "(price|amount|total) *: *(number|float|double)" src'
exit $fail
```

Then wire it as a gate in `stack.sh` so it actually blocks:

```bash
GATE_BACK_CMD='./mvnw -q test && bash loop/tests/project-test.sh'
```

Now your project rules are enforced by the same mechanism as the law's, and a
future agent cannot argue with them.

## The same split applies to taste

`loop/skills/` holds what the loop learned about how code should LOOK here:
naming, structure, idioms, UI tokens. The distiller writes them from run
experience, the maker receives them in its prompt, and a scoring pass retires
the ones that never help.

Those never ship with the skill, and they should not: another project's taste
is noise in yours. What ships is the MACHINERY that grows them.

## Upgrading without losing anything

```bash
bash <skill>/scripts/sync-law.sh    # law updated, everything of yours untouched
bash loop/tests/harness-test.sh     # the law's own assertions must pass
bash loop/tests/project-test.sh     # yours must pass too
```

If a law assertion fails after a sync, the law changed under you: read its
version notes before running a night on it. If a project assertion fails, the
new law is enforcing something you had been violating quietly.

## The rule to remember

**Anything true for every project belongs to the law. Anything true only here
belongs to the project half, and must survive every upgrade.** When you are
unsure which side something belongs to, ask whether a stranger's repo would
want it. If not, it stays home.
