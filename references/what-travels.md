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
night.

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

## When in doubt

Ask whether a stranger's repository would want it. If not, it stays home.
