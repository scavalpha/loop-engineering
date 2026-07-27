# Card format: units of work that cannot lie

A card is a markdown file in `loop/tasks/`, one card per file, kebab-case
name with a numeric prefix that fixes its family and sort position, for
example `20-export-csv-file-validation.md`.

## Structure

```markdown
# Human title of the card

SCOPE: front | back | full | <your-zone>
VALUE: P0 | P1 | P2 | P3

USE CASE:
What the user can do once this exists, in observable terms. One concern.

CONTEXT:
Facts the maker needs and cannot guess: contracts, file paths that already
exist, decisions already made, traps already hit. Keep it short and true.
Never paste raw tool output here without UTF-8 sanitizing it.

DONE WHEN:
- Observable criterion 1 (what a human would check on the running app)
- Observable criterion 2
- Tests: what proves it automatically, and with WHAT MOCKED (a gate must
  never depend on an external service being up)

PROBE: <one command, exit 0 = this aspect exists>
PROBE: <another command>
PROBE: cd <module> && <build-or-test command>
```

## Sort and family conventions

The queue is sorted by VALUE first (P0 before P1), then by filename. Prefixes
that the law treats specially:

| Prefix | Meaning |
| --- | --- |
| `00-F<gen>-<base>-fixes` | fix-lot card generated from reviewer findings, always P0 |
| `00-E2E-*` | end-to-end repair card, always P0 |
| `zz-E-<base>` | escalated retry of a failed card (sorts last, uses the escalation model) |

All three are REPAIR cards: the driver refuses to auto-complete them (green
probes on a repair card mean bad probes), and they leave the queue only when
their commit exists in history.

## Probe rules (each one paid for)

1. **Executable commands only.** `rg`, `grep -q`, `test -f`, a build, a unit
   test run. Never prose ("Verify that...").
2. **AND semantics, one assertion per line.** Three requirements means three
   PROBE lines.
3. **No `|` alternation inside patterns, no `||` between commands.** An OR
   can be true before the feature exists, and the card completes at birth
   with nothing built.
4. **No always-true constructs.** `|| true` and `&& echo OK || echo OK` make
   the probe unconditionally green. Both have been found in real cards.
5. **Discriminant: run every probe BEFORE writing the card.** The correct
   state today is FAIL (exit non-zero). If it passes today, it proves
   nothing about the work. For repair cards this is mandatory: require an
   artifact that only the fix can produce (a status file with an exact
   line, a marker only the repaired path emits, a count that changes).
6. **Case variants: use `-i`, not two probes.** `apercu` and `Apercu` as two
   AND probes forces both spellings to exist, which is absurd. `rg -i` once.
7. **Do not put the e2e suite execution in a PROBE.** Probe timeouts are
   short and sandboxes may lack ports. The full suite belongs to the run's
   e2e phase or to the card's DONE WHEN ("run bash loop/verify.sh --e2e
   yourself until 0 failed"). Static probes on the spec file are fine.
8. **Paths must exist or be created by the work.** A probe on a path that
   can never exist returns exit 2 and gets neutralized by the lint, so the
   card silently loses that requirement. Check spelling.

## Good and bad, from real cards

Bad (all really happened):

```
PROBE: rg -q "recherche|filtre|tri" src/app/pages/ged        # OR: lies
PROBE: rg -q "Plex" a.scss || rg -q "var\(--" a.scss         # OR: lied, card died
PROBE: rg "border-dashed" src && echo FAIL || echo OK        # always exit 0
PROBE: Verify the print button only prints the PV            # prose
PROBE: test -f e2e/parcours-validation.spec.ts               # passes today: scenery
```

Good:

```
PROBE: rg -q "searchDossiers" src/app/services/dossier.service.ts
PROBE: rg -iq "apercu" src/app/pages/ged/ged.html
PROBE: test -f docs/e2e-status.md
PROBE: grep -q "RESULTAT: 0 failed" docs/e2e-status.md
PROBE: cd backend && ./mvnw -q test
```

The `docs/e2e-status.md` pair is the repair-card pattern: the file does not
exist today (discriminant), the maker is instructed to write it only when the
suite is really green, with the exact result line, and the run's own e2e
phase then verifies the claim independently.

## Writing the DONE WHEN

Write it as the acceptance test a demanding human would run, in the product's
language, not the code's. Name the roles who act, the screens they see, the
state that changes. Two rules that saved rework:

- Business rules already won must be listed as PRESERVED (for example: "the
  frozen per-dossier circuit is not recalculated, the mandatory-document rule
  stays blocking"). Otherwise a maker "fixes" a failing test by deleting the
  rule the test was protecting.
- If a spec fails against a rule, say explicitly which side must move: "the
  test provides the missing document, the rule does not bend".
