---
name: loop-engineering
description: Build and operate an autonomous engineering loop on any local git project, with Claude Code, Codex, or any agent CLI as the maker. Use when the user wants an overnight coding loop, a self-improving build loop, autonomous card-based development, or wants to port a loop to a new repo. Triggers include "loop engineering", "overnight loop", "autonomous loop", "engineering loop", "boucle autonome", "run cards".
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
scripts/init-loop.sh    scaffold the loop into any git repo (one command)
scripts/loop.sh         the driver: pick, make, gate, commit or reset
scripts/probe-lint.sh   card linter (catches lying probes before they lie)
scripts/verify.sh       run the project gates by hand, same as the law does
scripts/lib.sh          shared functions (probe parsing, base normalization)
references/doctrine.md       the laws and why they exist
references/card-format.md    how to write cards that cannot lie
references/stack-contract.md the one file that adapts the loop to any stack
references/supervision.md    launch, monitor, close, failure classes
```

## Quickstart

From the root of the target project:

```bash
bash <skill-dir>/scripts/init-loop.sh
```

This creates `loop/` with the driver, a `stack.sh` contract pre-filled by stack
detection, and an example card. Then:

1. Edit `loop/stack.sh`: pick the agent (`LOOP_AGENT=claude|codex|custom`), fix
   the gate commands, write a one-paragraph `STACK_BRIEF`.
2. Write 2 or 3 real cards in `loop/tasks/` (read `references/card-format.md`
   first, bad probes are the number one cause of wasted nights).
3. Lint them: `bash loop/probe-lint.sh loop/tasks/*.md`
4. Dry-run the machinery: `LOOP_DRY_RUN=1 bash loop/loop.sh 5m`
5. First real run, supervised, short: `bash loop/loop.sh 1h`
6. Watch it: `tail -f loop/logs/run-*.log`. Never fire-and-forget.
7. When the run closes green, verify independently, then merge `loop/work`
   into your branch yourself. The loop never merges.

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

Set in `loop/stack.sh`:

```bash
LOOP_AGENT=claude          # Claude Code CLI
LOOP_MODEL=claude-opus-5   # optional model override

LOOP_AGENT=codex           # Codex CLI (prompts are UTF-8 sanitized for it)
LOOP_MODEL=gpt-5-codex     # optional

LOOP_AGENT=custom          # anything else, e.g. Hermes or a local runner
LOOP_MAKER_TEMPLATE='hermes -z "$(cat {PROMPT_FILE})"'
```

The maker always runs with the worktree as working directory. That worktree is
the blast radius: the law resets anything that does not gate green. For Claude
the preset uses non-interactive mode with permissions bypassed INSIDE the
worktree only. Read the warning in `references/stack-contract.md` before
changing that.

An optional independent checker reviews each green commit. By default the law
picks the opposite family automatically when the other CLI is installed
(`LOOP_CHECKER=auto`).

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

Measured on `scripts/loop.sh` (349 effective lines): the part a goal mode
would replace is the pick-work-judge loop with its deadline and stop file,
about 7 lines. Everything else has no equivalent in any goal mode, because
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
