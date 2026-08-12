# Doctrine: the laws and the incidents behind them

Every rule below was paid for in production: a lost night, a lying card, a
false green. The format is the rule, then what created it. Keep the incidents
with the rules: a rule whose origin is forgotten gets deleted by the next
person optimising, and the incident comes back.

**How to read this.** These pages were written when the work was driven by a
bash script wrapping a weak local model, so they describe mechanisms in terms
of that machinery: a driver, gates, probes, cards moving between directories.
You do not need any of that. Build the harness you judge necessary. What is
worth carrying is underneath the mechanism: WHY each guard exists, and what
happened when it was missing. Read it that way. If you build without probes,
the invariants to keep from sections 2 to 5 are only these: a completion check
proves nothing unless it fails before the work exists, a repair card never
closes without the defect being re-observed, and a commit message alone proves
nothing. The incidents and numbers here are testimony from the origin project;
their logs are not in this repository.

## 1. Isolation and atomicity

**The owner-provided project folder is the boundary.** Work directly in that
checkout, on its current branch or a local loop branch. Never create a clone or
a worktree as an implicit isolation mechanism. A worktree is allowed only when
the owner explicitly requests one in the current conversation, and then it
lives inside the project folder. Permission bypass is not isolation: if the
folder is not writable for the full window, the run does not start.
Origin: a loop escaped a workspace permission boundary by creating a clone in
another project folder, polluted the owner's disk, and still could not remain
autonomous.

**Atomicity.** One card, one cycle, one verdict. Green: exactly one commit.
Red: preserve the rejected diff as evidence when useful, then restore only the
loop-owned changes and prove the checkout clean. Never discard pre-existing or
owner-owned work. The commit message records the card and executed evidence.

## 2. Cards and probes

**Probes are the definition of done, so they must be impossible to satisfy by
accident.** The rules, each from a real lie:

- One assertion per PROBE line, combined with AND semantics (all must pass).
- No alternation `|` inside a grep/rg pattern, and no shell `||` between
  commands. Origin: a card shipped as "done" because the second branch of
  `rg A || rg B` was true since v1 of the code, feature never built.
- No always-true probes (`... || true`, `... && echo OK || echo OK`). Both
  observed in the wild, both make a card auto-complete at birth.
- No prose probes ("Verify that the screen shows..."). They are not
  executable, and worse, a driver that treats non-zero as red will revert
  good code because prose never exits 0. Neutralize them.
- Dry-run every probe at seed time. Exit code 2 or 127 means the probe
  itself is malformed (bad flag, missing file argument, wrong regex dialect)
  and can never turn green. Neutralize it and say so. Origin: `rg -E` (which
  is an encoding flag, not extended-regex) made a probe permanently red and
  19 minutes of correct work got reverted, twice.
- A probe that already passes before any work exists is not proof, it is
  scenery. For NEW-feature cards the driver may auto-complete a card whose
  probes all pass (the feature landed earlier). For REPAIR cards this exact
  situation means the probes are non-discriminant, see rule 4.

**Card sizing.** One card is one buildable, provable concern, sized for one
agent session (15 to 30 minutes of agent work). Bigger intents become several
cards ordered by dependency, or an explicit multi-step card with a Playwright
or integration spec as the deliverable.

## 3. Auto-completion (AUTODONE)

A card whose runnable probes ALL pass may be marked done without spending a
cycle, with three guards, each from an incident:

- At least one runnable probe is required. Zero-probe cards never auto-done.
- Cards carrying OR-probes are excluded (the OR may be lying, see above).
- Repair cards are excluded entirely, see next rule.

The same applies late: a cycle that changed nothing but whose card's probes
all pass is "done, delivered earlier", not an infra failure. Origin: an
already-done card re-picked at night was read as a dead model and the driver
spent 7 hours in a heal loop.

## 4. Repair cards are special

A repair card (fix-lot `00-F*`, e2e repair `00-E2E*`, escalation `zz-E-*`)
describes a defect that WAS OBSERVED. Therefore:

- If its probes all pass before any work, the only sane conclusion is that
  the probes are bad, never that the defect fixed itself. The driver refuses
  auto-done and routes it through maker plus gate, saying why in the log.
  Origin: the author of the law himself wrote a repair card whose probes
  (`test -f` on existing files, gates already green) were all green, and the
  card was marked done with 13 specs still red. If the human who wrote the
  rulebook reproduces the bug class, the guard belongs in the law, not in
  writing discipline.
- The only legitimate exit without a cycle is HISTORY: a commit
  `feat: <card> [loop` in the base proves the gate validated that work. Check
  this at seed time and retire the card. Origin: after closing the auto-done
  door, already-merged repair cards came back every run and burned a cycle
  each, forever.

## 5. Fix-lots and the generation cap

After a green, an independent reviewer (the chair) inspects the shipped diff.
Findings become ONE new card `00-F<gen>-<base>-fixes`, VALUE P0, and nothing
is reverted (fix-forward: the code is committed and working, refine it).

- **P0 is not optional.** Origin: fix cards born without VALUE sank below
  feature cards and the e2e stayed red for a whole run while features piled
  on top of the regression. A constated regression outranks any new feature.
- **The base name must be normalized to a fixed point** before naming and
  counting: strip every repair prefix (`00-F<n>-`, `00-E2E-`, `zz-E-`) and
  every `-fixes` suffix, repeatedly, until stable. Origin: gen 3 of a fix was
  named `00-F1-00-F1-00-F1-<base>-fixes-fixes-fixes`, each generation saw a
  "new" base, each got a fresh counter, and the cap never fired.
- **Counters persist in the project checkout** (see rule 1).
- Above the cap (default 2): stop generating fix cards for that base and
  surface the findings to the owner instead. Endless fix-of-fix is churn.

## 6. Judge independence

The judge's family must differ from the maker's AND from whoever verified the
work (one rule, same everywhere in this skill). A judge from the maker's family
rubber-stamps its own idiom and finds the same blind spots. If only one CLI is
installed, run without a checker rather than with a same-family one, and say
so in the report.

Codex-specific: its CLI rejects arguments that are not valid UTF-8. Sanitize
every prompt (`iconv -f UTF-8 -t UTF-8 -c`) before exec. Origin: a truncated
box-drawing character pasted into a card context hard-failed every cycle that
touched it.

## 7. Assembly truth: the runtime gate

Per-card gates (build plus unit tests) cannot see integration regressions.
Proven case: ten consecutive green cards, every gate green, and the full
end-to-end suite at 47 passed / 13 failed, all 13 in screens that read the
data those cards had refactored.

- Run the FULL e2e suite regularly (every run close at minimum), not only
  per-card.
- Before any merge, verify independently: gates plus full e2e, executed by
  you, not trusted from a report file. A maker-written status file is a
  claim, the suite run is the proof.
- If the suite serves a BUILD artifact (a dist folder), check its freshness
  against the sources and rebuild if stale, otherwise you test last week's
  app and get phantom failures. If it serves via a dev server that compiles
  from source, this does not apply.
- A red e2e on a loaded machine is not a verdict, see rule 9.

## 8. Infra failure classes (never blame the card)

The driver classifies failures BEFORE routing a card to retry or escalation.
Signatures and responses, each from a lost night or a burned window:

| Class | Signature | Response |
| --- | --- | --- |
| Provider overloaded | `529`, `503`, `overloaded`, `service unavailable` in the cycle log | pause ~3 min, retry same card unchanged, cap 3 episodes per run, then stop the run as infrastructure-degraded, never reclassify a provider failure as the card's red |
| Network lost | `ECONNREFUSED`, `ENOTFOUND`, `ETIMEDOUT` AND the provider endpoint unreachable | pause in 5 min slices until the endpoint answers, card untouched |
| Rate limit / quota | `rate limit`, `429`, `try again at HH:MM`, `quota` | reactive pause in 20 min slices, card untouched (the full ancestor law parses the provider's own reset time, add that if your provider prints one) |
| Fast-fail | two consecutive failures under 60 s and the maker does not answer a ping | it is infra, not the card: pause, do not route |

**The proactive quota gate rule.** A gate that pauses on a quota ESTIMATE must
obey two limits: if the metric does not move across two readings, resume (a
frozen metric means the sensor is dead or the quota is non-refilling, waiting
is wrong in both cases), and never pause more than a fixed number of slices.
Origin: a provider silently replaced its 5-hour quota window with a weekly
one, the probe kept reading a frozen 83 percent, and the gate paused an entire
night, 10 minutes at a time, until the deadline. Doctrine: only a REAL error
from the provider justifies a long wait, an estimate never does.

## 9. The machine is part of the system

- **Reap orphans every cycle and at close**: any process whose command line
  points into the project folder (JVMs, dev servers, node, headless browsers) and
  that is not the agent itself. Leaked processes accumulate across cycles and
  saturate the machine.
- **Headless Chromium on macOS**: force GPU off (`--disable-gpu` family
  flags) for every Playwright launch path, including screenshot side-scripts,
  and kill `headless_shell` explicitly after suites.
- **A saturated machine produces false reds.** Proven case: same commit,
  the run's own e2e green, the manual re-verification 7 failed then killed at
  RC=137, swap at 94 percent, backend OOM-killed mid-suite. Before believing
  a red that contradicts a green, check memory and swap. Prefer verifying on
  a quiet machine, and prefer night runs if the workday loads the box.
- **Lock files**: a maker that edits the dependency manifest must regenerate
  the lock file in the same card, and the install command in preflight will
  catch the desync (`npm ci` style, fail loud, no silent flag).

## 10. Operations

- **No run without an explicit owner order.** The words come from the owner
  in the current conversation, never inferred, never carried over.
- **Supervise, never fire-and-forget.** Check roughly every 10 minutes early
  in a run. Intercept build-and-revert loops before they eat the night. The
  checker is whoever drives, human or agent: an agent driver watches its own
  run, the owner reads the report.
- **A net-caught anomaly is still an anomaly.** The resurrector restarting a
  dead driver, the reaper killing an orphan: those are symptoms captured, not
  problems solved. Diagnose immediately.
- **Close runs completely.** Kill the scheduler entry AND delete its config
  (a `launchctl bootout` does not survive a reboot if the plist remains, and
  a stale plist re-launched a finished run with a past deadline interpreted
  as tomorrow). Purge the night-plan marker on legitimate ends so any
  resurrector knows the run is over.
- **The owner merges.** Greens accumulate on the loop branch. Merging into
  the base branch is a human decision after independent verification.

## 11. What is knowledge, and what is this project

Keep two things apart. The doctrine above is knowledge: it travels to the next
project unchanged. Everything a project knows about itself, what it is, its
conventions, its traps, the checks written for defects that cost it dearly,
belongs to that project and must survive every upgrade of anything else.

When unsure which side something belongs to, ask whether a stranger's
repository would want it. If not, it stays home. See `what-travels.md`.

A corollary worth stating: nothing in this doctrine should name a project, a
directory or a command. The moment it does, it has stopped being knowledge and
started being configuration.
