# Beyond code: loops on books, documents, datasets

Nothing in the law says "code". It says: a card is a unit of work, a maker
produces it, and GATES decide whether it survives. The only real requirement
is that something mechanical can say yes or no.

Replace "compiler and tests" with "whatever can mechanically check this
domain", and the loop works on prose, documentation, datasets, translations,
slide decks.

What never changes: green is a commit, red is a full reset, the maker never
grades itself, and the owner merges.

## Worked example: a novelist writing chapters

**The project**: a manuscript in git. One markdown file per chapter, plus a
story bible with characters, timeline and established facts.

```
manuscrit/
  bible.md            characters, places, timeline, facts that must hold
  chapitres/
    01-arrivee.md
    02-la-lettre.md
  loop/               the law
  docs/domain-rules.md   <- the spec: what this book IS
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

SCOPE: full
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

PROBE: test -f chapitres/09-le-depart.md
PROBE: bash outils/mots.sh chapitres/09-le-depart.md 2000 4000
PROBE: bash outils/personnages.sh chapitres/09-le-depart.md bible.md
PROBE: vale --minAlertLevel=error chapitres/09-le-depart.md
```

**The gates** in `loop/stack.sh` become prose checks:

```bash
STACK_NAME="mon-roman"
ARCH_PROFILE="lib"                  # no front, no back, no ports
PROJECT_DOMAIN="un roman en francais, troisieme personne limitee"

GATE_FRONT_CMD='vale --minAlertLevel=error chapitres/'
GATE_BACK_CMD='bash outils/coherence.sh'   # your own consistency checks

STACK_BRIEF='Manuscrit en markdown, un fichier par chapitre dans chapitres/.
La bible (bible.md) fait autorite sur les personnages, lieux et faits etablis:
un chapitre ne peut jamais la contredire, il peut seulement l ajouter. POV
troisieme personne limitee sur Mara, temps passe. Style: phrases courtes,
pas d adverbes en -ment en cascade, dialogues sans incises redondantes.'
```

`outils/coherence.sh` is yours to write, and it is where the real value sits.
Fifty lines of shell can already check: every capitalised name in a chapter
appears in the bible, no chapter references an event scheduled later in the
timeline, word counts stay in range, no chapter number is duplicated or
missing, tense markers do not drift.

The checker (a different model family) then reviews each accepted chapter for
what no script can see: does the promise of the card actually land, does the
voice hold, is a plot thread dropped. Its findings become fix cards, P0,
fix-forward.

## What the loop can and cannot guarantee here

It **can** guarantee: the chapter exists, it respects your formal
constraints, it contradicts nothing established, the vocabulary passes your
style rules, the bible stays in sync, and nothing regressed in earlier
chapters. That is a great deal of the tedium of a long manuscript.

It **cannot** guarantee that the writing is good. Beauty is not mechanically
checkable, and a loop that pretends otherwise lies to you. The honest split:
the loop owns consistency and constraints, you own taste. Read every chapter.
Merge nothing you have not read.

This limit is not specific to prose, it is the same everywhere. In code, the
gates prove it builds and behaves; they never prove the design is wise.

## Other non-code domains that fit

| Domain | Gates that actually work |
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

You can start small: one probe that checks existence and one that checks a
format constraint is already better than nothing, and you will discover the
sharper checks by watching what slips through.
