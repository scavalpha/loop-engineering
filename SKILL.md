---
name: loop-engineering
description: Build and operate an autonomous work loop on any local git project, with Claude Code, Codex or Hermes as the maker. Cards are picked, executed by an agent in a throwaway worktree, then judged by gates (build, tests, probes): green becomes a commit, red is reset. Works beyond code too (manuscripts, docs, datasets) wherever something mechanical can verify the work. Use when the user wants an overnight loop, a self-improving build loop, autonomous card-based development, or wants to install a loop on a repo. Triggers include "loop engineering", "overnight loop", "autonomous loop", "boucle autonome", "run cards".
---

# Loop Engineering

A loop is a deterministic bash LAW wrapping a probabilistic MAKER. The law picks a
card (a small, provable unit of work), hands it to a coding agent, then judges the
result with compilers, tests and probes. Green survives as a commit. Red is reset
to zero. The agent's opinion of its own work is never the verdict: the gates are.

This skill was distilled from months of production runs on real banking projects
(80+ hardening revisions of the law). Every rule in it was paid for by a lost
night, a lying card, or a false green. The scripts here are a clean, portable
rewrite of that law.

## What you get

```
scripts/init-loop.sh    install the law into a git repo (one command)
scripts/sync-law.sh     re-vendor a newer law without touching your contract
law/                    THE LAW: 19 scripts, ~6800 lines, 84 hardening revisions
  loop-overnight.sh       the driver: pick, make, gate, commit or reset
  run-cycle.sh            one card, one agent session, one verdict
  verify.sh / e2e.sh      the gates and the runtime gate
  critic.sh               product critic (looks at the running app)
  distill.sh              turns run experience into hints and skills
  council.sh              arbitration when a card keeps failing
  resurrect.sh            restarts a driver that died before its deadline
  tests/harness-test.sh   700+ assertions guarding the law itself
references/doctrine.md       the laws and the incident behind each one
references/card-format.md    cards and probes that cannot lie
references/stack-contract.md the one file that adapts the loop to any stack
references/supervision.md    launch, monitor, close, failure classes
references/agents.md         casting maker/checker/cartographer/critic
references/getting-started.md from a spec document to a running loop
references/beyond-code.md    loops on books, docs, datasets (non-code)
references/generic-vs-project.md  what travels vs what stays and is learned
```

The law is VENDORED into the project at install time: afterwards the project
is autonomous, and `sync-law.sh` re-vendors a newer version on demand without
ever touching `loop/stack.sh`, your cards or your state.

## How to read this skill (you are an agent, not a copier)

Two things are shipped here and they have very different weights.

**The doctrine is the contract.** `references/doctrine.md` and the ten rules
below are not style preferences: each one was paid for by a lost night, a
lying card or a false green. You cannot re-derive them from first principles,
because they are counter-intuitive by nature (a green probe on a repair card
means the PROBE is wrong; a proactive quota gate must resume on a frozen
metric; a same-family reviewer is worse than none). Follow them. If you think
one is wrong, say so explicitly to the owner rather than silently dropping it.

**The law in `law/` is a reference implementation, not scripture.** It is a
production driver hardened over 80+ revisions, so it will save you days, and
installing it as-is is usually the right call. But you are a reasoning agent:
if the project needs something different, adapt it. Concretely you are
expected to:

- write `loop/stack.sh` yourself after interviewing the owner, never guess it;
- adapt the gates to what this project can actually verify (a novel has no
  compiler, a mobile app has no Playwright);
- diagnose and fix what the law's harness reports on THIS project instead of
  treating a failing assertion as fate: some of them guard the law, others
  guard artifacts a given project may not have;
- write project-specific assertions when you catch the same mistake twice
  (see `references/generic-vs-project.md`);
- improve the law when you find a real defect in it, with a test and the
  incident recorded in the comment, exactly as its own history does.

What you must NOT do: dilute a guard because it is inconvenient, mark work
done on a maker's word, or launch a run without the owner's explicit order.

## Onboarding: interview the owner before writing anything

When someone asks you to set up a loop on their project, do NOT guess their
setup and do NOT dump a config on them. Detect what you can, then ASK the rest
as multiple-choice questions (use the AskUserQuestion tool if you have it, a
numbered list otherwise). One pass, then you write `loop/stack.sh` yourself.

**First, detect silently** (never ask what you can observe):

```bash
for c in claude codex hermes; do command -v $c >/dev/null && echo "have: $c"; done
ls package.json pom.xml build.gradle* Cargo.toml go.mod pyproject.toml \
   pubspec.yaml *.xcodeproj Gemfile 2>/dev/null      # stack fingerprint
git rev-parse --show-toplevel 2>/dev/null            # is it a git repo at all
ls docs/*.md README.md 2>/dev/null                   # is there a spec already
```

**Then ask, in this order.** Offer only options that the detection supports:
proposing Codex to someone who does not have it wastes their time.

1. **Maker** (the agent that writes the code): the CLIs found, one per option.
   Recommend their strongest coding model. Say what it costs: a frontier maker
   on a 7-hour night is expensive, a local model via Hermes is nearly free and
   noticeably weaker.
2. **Checker** (reviews each green diff): offer the OTHER families found, plus
   "none". State the rule: same family as the maker finds nothing, so if only
   one CLI exists, "none" is the honest answer.
3. **Project type**: web fullstack / API only / mobile / CLI / library. This
   sets `ARCH_PROFILE` and decides whether screen-oriented organs run at all.
4. **The spec**: "you have a requirements doc" (ask for the path, it becomes
   `docs/domain-rules.md`) / "no, help me write one" / "skip, I will write
   cards myself". The cartographer needs this to generate cards.
5. **Runtime gate**: Playwright / Detox or Maestro / other command / none.
   If none, warn plainly: build and unit tests only means assembly
   regressions reach them late.
6. **Run length for the first run**: 1h supervised (recommended) / 2h / a full
   night. Never propose a night as the first run on a fresh repo.
7. **Environment needs**: does the project need a database or another service
   up to run its tests? (yes, ask for the health command / no). This sets
   `DB_REQUIRED` and prevents both a false "REFUSE" and a silent failure.

**Then, without asking**: derive the gate commands from the stack fingerprint,
write `loop/stack.sh`, run `bash loop/verify.sh` to prove the gates are green
on the untouched tree, and report what you configured. If a gate is red on the
clean tree, STOP and say so: a loop on a red base makes every verdict
meaningless.

**What you must never do at onboarding**: launch a run. Setting up and running
are two decisions, and the second belongs to the owner (see rule 10).

## Quickstart

From the root of the target project:

```bash
bash <skill-dir>/scripts/init-loop.sh
```

This vendors the law into `loop/`, writes a `stack.sh` skeleton with what it
could detect, and creates `docs/domain-rules.md` (the spec the cartographer
reads). Then:

1. Fill `loop/stack.sh`: casting, gate commands, `STACK_BRIEF`. If you are an
   agent doing this for someone, run the onboarding interview above first.
2. Write the spec in `docs/domain-rules.md` (rules and use cases, not tasks).
   The cartographer turns it into cards when the queue runs dry.
3. Seed 2 or 3 small cards yourself for the first run (read
   `references/card-format.md`: bad probes are the top cause of wasted nights).
4. Prove the base is sound: `bash loop/verify.sh` must be GREEN on a clean
   tree. A loop on a red base makes every verdict meaningless.
5. First run, short and supervised: `bash loop/loop-overnight.sh +1h`
6. Watch it: `tail -f loop/logs/*.log`. Never fire-and-forget.
7. When it closes: verify independently (gates + full runtime suite, quiet
   machine), then YOU merge the loop branch. The loop never merges.

## The ten iron rules

These are the condensed doctrine. The full reasoning is in
`references/doctrine.md`, read it before changing the law.

1. **The gate decides, never the maker.** A card is green when the project
   builds, the tests pass and every probe exits 0. Prose claims are noise.
2. **Atomic or nothing.** Work happens in a disposable worktree. Green becomes
   one commit. Red becomes `git reset --hard`. There is no partially-done card.
3. **Probes are AND, discriminant, executable.** One assertion per PROBE line.
   No `|` alternation inside a pattern, no `||` between commands, no prose, no
   always-true. A probe that already passes before the work exists is a lie.
4. **A repair card can never auto-complete.** If its probes already pass, the
   probes are wrong, not the defect gone. Repair cards leave the queue only
   when their fix is a commit in history.
5. **Judge and maker come from different families.** Claude makes, Codex
   reviews, or the reverse. A model reviewing its own family finds nothing.
6. **Regression outranks new features.** Reviewer findings on shipped work
   become P0 fix cards. Fix generations are capped (default 2) with counters
   persisted outside the worktree, and the fix of a fix keeps the SAME base
   name, otherwise the cap counts nothing.
7. **Per-card gates do not see assembly breakage.** Run the full end-to-end
   suite regularly and always before a merge, on a quiet machine. Ten green
   cards can still assemble into a broken product.
8. **Infra failure is never the card's fault.** Provider overload (529/503),
   lost network, rate limits: pause and retry the same card, never blame it,
   never route it to escalation. And a proactive quota gate must never hold a
   night hostage on a frozen metric: if the reading does not move, resume.
9. **Reap everything, every cycle.** Kill worktree orphans (JVMs, dev servers,
   headless browsers) at the top of each cycle and at close. A saturated
   machine produces false reds that look exactly like real regressions.
10. **The owner launches, the owner merges.** Never start a run without an
    explicit order. Supervise every run. An anomaly caught by a safety net is
    still an anomaly: diagnose it now, not tomorrow.

## Choosing the maker agent

Set the casting in `loop/stack.sh`. The law routes by model family
automatically, so naming a model is usually enough:

```bash
LOOP_MAKER_KIND=claude     # claude | codex | hermes
LOOP_MAKER=""              # model id, empty = the CLI default
LOOP_LOT_CHAIR=codex       # the CHECKER: a DIFFERENT family than the maker
LOOP_ESCALATION_MAKER=""   # different model for retries after a red
LOOP_NO_LOCAL_LLM=1        # 1 = frontier casting, no local model required
```

All three CLIs are first-class. Hermes has the richest support (loop-scoped
profile with a write-boundary hook, provider fallback, scoped memory, and
local models via MLX or Ollama). Codex prompts are UTF-8 sanitized before
exec, because its CLI rejects invalid UTF-8 arguments. Claude runs
non-interactive with permissions bypassed INSIDE the worktree.

Full casting guide, per-CLI specifics and budget tradeoffs:
`references/agents.md`.

The containment that makes permission bypass acceptable is the disposable
worktree plus the hard reset on red. Never point a loop at a checkout holding
secrets, and never run it outside a worktree.

## Relation to goal modes (/goal, Codex goals, Hermes goal mode)

All three agents ship a persistent-goal feature: Claude Code `/goal` ("keep
working until the condition is met"), Codex `thread_goals` (statuses active /
paused / blocked / usage_limited / budget_limited / complete), Hermes
`goals.py` (its docstring calls it "the Ralph loop"). They are the same
mechanism: an objective survives across turns, an auxiliary model is asked
"is this satisfied yet?", and a continuation prompt is fed back until it says
yes or the turn budget runs out.

**They are orthogonal to this skill, not a replacement, and the difference is
the one that matters.** A goal mode makes a MODEL the judge. This skill makes
compilers, tests and probes the judge, gives each card a fresh session, and
makes the outcome atomic (one commit, or `git reset --hard`). A model asked
whether its own work is done is exactly the mechanism that produces the lying
greens rule 1 exists to prevent.

**Compose them, and the weakness disappears.** A goal is only as good as its
stop condition, so give it one that is machine-checkable instead of a matter
of opinion. The loop supplies exactly that:

```
/goal keep running loop cycles until `bash loop/verify.sh --e2e` exits 0
      and no P0 card remains in loop/state/queue
```

Now the goal layer contributes what it is genuinely good at (intent that
survives restarts, budget and usage limits, resume), and the loop contributes
the verdict. The judge no longer guesses: it reads an exit code.

Two rules when composing:

- Never let a goal's stop condition be a subjective claim ("until the feature
  works well"). Point it at `verify.sh`, a probe, a queue count, a commit.
  Watch the wording each agent nudges you toward: Claude Code says "keep
  working until the condition is met" (it asks for a condition), Codex says
  "set a goal to keep pursuing" (it asks for an intent, and nothing prompts
  you for a stop criterion). On Codex especially, write the checkable
  condition yourself or the judge falls back to opinion.
- Keep the owner doctrine: a goal that relaunches runs is still a run. It
  needs the same explicit order and the same supervision. Set a turn budget.

Hermes goes furthest in this direction already: `run_kanban_goal_loop` drives
one Ralph loop PER CARD with explicit `kanban_complete` / `kanban_block`
terminators. That is convergent with the card model here, and it is the best
place to plug a custom-agent loop if you use Hermes.

### Why a goal mode cannot be the loop's engine

Every goal implementation is scoped to a SESSION: Hermes says "the standing
goal for this session" and persists it under `goal:<session_id>`, Codex keys
its table by `thread_id`, Claude Code attaches it to the conversation. The
loop is the opposite shape by design: the driver runs headless (launchd,
nohup, cron) with NO agent session alive, and it spawns a FRESH session per
card, then throws it away.

That is not an implementation detail, it is the point:

- one session per card keeps each context small and clean, so card 15 is not
  polluted by the 14 before it, and cost stays bounded;
- a card's failure cannot contaminate the next one, because there is nothing
  shared to contaminate;
- the driver survives what a session cannot: it is a process, restartable by
  a scheduler, whereas a goal dies with its session.

Running a 7-hour night as one standing goal means one session accumulating
every diff, every error and every retry: context bloat, drift, and a bill
that grows superlinearly. That is the failure mode the card model exists to
avoid.

### What this skill deliberately does not reinvent

Measured on the driver: the part a goal mode would replace is the
pick-work-judge loop with its deadline and stop file, a few dozen lines out of
thousands. Everything else has no equivalent in any goal mode, because
goal modes were built to persist an intent, not to judge work:

| Concern | Who owns it |
| --- | --- |
| Persist intent across restarts, budgets, resume | **goal mode** (use it) |
| Recurring wall-clock scheduling | **cron / launchd / `/loop`** (use them) |
| Task list for a human to follow | **the agent's own todo tools** (use them) |
| Gates as the verdict, probes, discriminance | this skill |
| Atomic commit-or-reset in a throwaway worktree | this skill |
| Repair cards that cannot self-complete | this skill |
| Infra failure classes that never blame the card | this skill |
| Cross-family review, capped fix-lot generations | this skill |
| Orphan reaping, e2e assembly truth | this skill |

So: delegate scheduling and intent persistence to the tools that already do
them, and keep this skill for the verdict. That is the composition described
above, not a rewrite of either side.

## Operating an existing loop

When the user asks you to run, watch or debug a loop that is already installed:

1. Read `loop/stack.sh` first, then `loop/state/report-*.md` and the last
   `loop/logs/run-*.log`. The journal tells you what the law decided and why.
2. Diagnose infra-looking failures against `references/supervision.md`
   (failure classes table). Check machine memory before believing a red e2e.
3. Improve the LAW, not the instance: if a failure class repeats, the fix
   belongs in `loop.sh` or in the card, with a test, not in a one-off manual
   touch-up of the worktree.
4. Keep the anti-leak rule: the law and the scripts never contain project
   names, stack commands or ports. All of that lives in `stack.sh`.

## Writing cards for the user

When asked to seed cards, follow `references/card-format.md` strictly. The
short version: describe the observable behavior wanted (DONE WHEN), give probes
that FAIL today and will pass only when the feature exists, tag VALUE (P0 to
P3), keep one card one concern, and never write a probe you have not executed
yourself first.
