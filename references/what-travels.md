# What travels, and what stays

Two kinds of knowledge live in a loop, and confusing them makes a project
either unportable or amnesiac.

**What travels** is the doctrine: how to shape a goal, what has failed before,
why a reviewer must come from another family. True on every project, worth
carrying to the next one.

**What stays** is everything a project learned about itself: what it is, its
conventions, the traps it has already sprung, the checks written for defects
that cost it dearly, the priorities of its owner. Useless elsewhere, precious
here, and it must survive every upgrade of anything else.

A loop with only the first is competent but naive. A loop with only the second
is a pile of notes.

## Growing what stays

The signal that something belongs in a project's own memory is simple: **a
class of error that recurs is a missing check, not a careless agent.**

The first time a mistake happens, fix it. The second time, write down what
would have caught it, and make that part of what you verify from then on. That
is how a loop gets better on a project rather than restarting from zero every
run.

Examples of what earns its place:

- "no component may import the ORM directly, it goes through a repository"
- "every endpoint returning money uses the Money type, never a float"
- "no test may hit the network"
- "a character may only be introduced in the story bible"

Each of those is enforceable, and each exists because someone violated it.

## Taste

A project also accumulates taste: naming, structure, idioms, what its screens
should feel like. Feed it to whoever does the work, and drop the rules that
never help. Another project's taste is noise in yours, so this never travels.

## Reviewing what you kept

Written memory rots as surely as a queue does: a check written for a real
defect goes false when the product improves, a convention gets superseded, a
lesson stops applying. Revisit it on the same rhythm as the queue.

The question to ask of each item: **would this still catch the thing it was
written for, or does it now only catch change?** The second kind is worse than
useless, it teaches everyone to ignore the alarm.

## When in doubt

Ask whether a stranger's repository would want it. If not, it stays home.
