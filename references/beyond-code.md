# Beyond code: loops on books, documents, datasets

Nothing in this doctrine says "code". It says: work is done when something can
verify it. The only real requirement is that something can settle the question
without asking a model to grade itself.

Replace "compiler and tests" with "whatever can mechanically check this
domain", and the loop works on prose, documentation, datasets, translations,
slide decks.

What never changes: success is a commit, failure is a clean reset, nobody
grades their own work, and the owner merges.

## Worked example: a novelist writing chapters

**The project**: a manuscript in git. One markdown file per chapter, plus a
story bible with characters, timeline and established facts.

```
manuscrit/
  bible.md            characters, places, timeline, facts that must hold
  chapitres/
    01-arrivee.md
    02-la-lettre.md
  loop/tasks/         the cards: one per chapter or revision pass
  docs/domain-rules.md   the spec: what this book IS
```

**The spec** (`docs/domain-rules.md`) carries the constraints the book must
respect, exactly as business rules would:

```markdown
# The book, rules and arc

## Arc
- Part 1 (ch. 1-8): the village, the letter arrives, Mara refuses to leave
- Part 2 (ch. 9-18): the journey, Mara learns her father lied

## Rules
- Point of view: third person limited, always Mara, never head-hopping
- Tense: past. No present-tense narration outside quoted letters
- No character appears in a chapter without existing in bible.md
- No fact contradicts an established fact in bible.md
- A chapter is 2000 to 4000 words
- Chapter titles are noun phrases, never sentences
```

**A card** = a chapter, or a revision pass:

```markdown
# Chapitre 9, le depart au petit matin

VALUE: P1

USE CASE:
Mara leaves the village before dawn, alone, having chosen not to wake her
mother. The reader must feel the cost of that silence, and learn, through what
she packs, that she expects never to return.

DONE WHEN:
- The chapter exists, respects the POV and tense rules, 2000 to 4000 words
- Every named character already exists in bible.md
- bible.md is updated with any new fact the chapter establishes
- No fact contradicts the bible
```

**What "it builds and tests pass" becomes here**: a prose linter over the
chapters, plus a consistency script you write yourself. Fifty lines of shell
already check a great deal: every capitalised name appears in the bible, no
chapter references an event scheduled later in the timeline, word counts stay
in range, no chapter number is duplicated or missing.

That consistency script is yours to write, and it is where the real value
sits: you know what your book must never contradict.

The checker (a different model family) then reviews each accepted chapter for
what no script can see: does the promise of the card actually land, does the
voice hold, is a plot thread dropped. Findings about constraints and
consistency become the next card, at top priority, and nothing gets reverted.
Findings about taste, whether the scene lands, whether the voice sings, are
observations handed to the owner, never a gate: a model grading beauty is
still a model grading itself.

## What the loop can and cannot guarantee here

It **can** guarantee: the chapter exists, it respects your formal
constraints, it contradicts nothing established, the vocabulary passes your
style rules, the bible stays in sync, and nothing regressed in earlier
chapters. That is a great deal of the tedium of a long manuscript.

It **cannot** guarantee that the writing is good. Beauty is not mechanically
checkable, and a loop that pretends otherwise lies to you. The honest split:
the loop owns consistency and constraints, you own taste. Read every chapter.
Merge nothing you have not read.

This limit is not specific to prose, it is the same everywhere. In code, building and testing prove it works; they never prove the design is wise.

## Other non-code domains that fit

| Domain | What settles the question |
| --- | --- |
| Technical documentation | link checker, code blocks executed in a sandbox, spell check, "every public API is documented" script |
| Translation | terminology glossary check, untranslated-segment detector, placeholder and tag integrity, length ratio bounds |
| Datasets | schema validation, referential integrity, distribution sanity checks, no PII regex |
| Legal or policy documents | required-clause presence, defined-terms consistency, cross-reference resolution |
| Slide decks | rendered export succeeds, no overflowing text box detected, one message per slide heuristic |

## The rule that decides whether a loop fits your domain

Before starting, answer one question: **what can mechanically prove this piece
of work is done?**

- A clear answer means the loop will serve you well.
- A vague answer ("it looks right") means you would be building a machine that
  asks a model to grade itself, which is the exact failure this law exists to
  prevent. Either find the mechanical check, or do that work by hand.

Start small: checking that the piece exists and respects one format
constraint already beats nothing, and you will discover the sharper checks by
watching what slips past you.
