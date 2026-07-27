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
references/native-mode.md    run the loop with no driver process (agent IS the driver)
references/generic-vs-project.md  what travels vs what stays and is learned
```

The law is VENDORED into the project at install time: afterwards the project
is autonomous, and `sync-law.sh` re-vendors a newer version on demand without
ever touching `loop/stack.sh`, your cards or your state.

## The request you will most often receive

> "Install the loop engineering skill and start a loop on this project."

That single sentence is an order to SET UP, and an order to run the FIRST run
once setup is proven. Here is the whole sequence. Do not skip steps, and do
not reorder them: each one exists because skipping it wasted a night.

```bash
# 1. the skill itself (skip if already installed)
git clone <skill-repo> ~/dev/loop-engineering
ln -s ~/dev/loop-engineering ~/.claude/skills/loop-engineering   # Claude Code
# Codex: add a line in AGENTS.md pointing at the SKILL.md
# Hermes: point your agent at the SKILL.md

# 2. install the law into THIS project (from its root)
bash ~/dev/loop-engineering/scripts/init-loop.sh
```

```
3. INTERVIEW the owner (see the section below). Detect the CLIs and the stack
   silently, then ask what you cannot observe: maker, checker, project type,
   where the spec lives, runtime gate, first-run length, environment needs.

4. WRITE loop/stack.sh from their answers. Never invent gates: ask, or read
   the project's CI config and confirm what you found.

5. WRITE docs/domain-rules.md if they have a spec elsewhere (copy it in) or
   help them draft one. The cartographer needs it to produce cards.

6. PROVE the base: bash loop/verify.sh must be GREEN on an untouched tree.
   Red base => STOP and report. Every verdict would be meaningless.

7. SEED 2 or 3 small cards, over-probed, from their spec. Lint them: each
   probe must FAIL today (run them and show it).

8. CONFIRM before launching: state the casting, the deadline, what will be
   spent, and that greens land on a branch you will NOT merge for them.

9. RUN. Two ways, pick with the owner:
   - AGENT MODE (default, and what you should reach for first): you run the
     loop yourself. Hold the intent with your goal feature, execute each card
     in a SUB-AGENT so contexts stay isolated, run the gates yourself, commit
     or reset. No process to babysit, failures visible immediately. See
     references/native-mode.md.
   - DRIVER MODE (unattended nights): bash loop/loop-overnight.sh +1h, then
     watch the log. Choose this when nobody will be awake, not by default.

10. CLOSE: verify independently (gates + runtime suite), summarise what is
    mergeable, and let the OWNER merge. You never merge.
```

If any step cannot be satisfied (no coding CLI installed, not a git repo, no
test command exists, gates red), stop there and say precisely what is missing.
A loop set up on a broken base produces confident garbage, which is worse than
no loop.

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

## What actually matters (and what is scaffolding)

This law grew around a WEAK maker: a small local model that had to be told
everything and defended against. Much of its machinery is the shadow of that
executor. If your maker is a reasoning model, most of it is optional, and
treating it as mandatory makes things worse, not safer.

**The four things that survive any maker.** These are not instructions to an
executor, they are facts and structure:

1. **Gates.** Nobody can *reason* that a project compiles. You run the build,
   the tests, the runtime suite. Exit codes, not opinions. This is the only
   thing that makes a green trustworthy.
2. **Atomicity.** Green becomes one commit, red becomes `git reset --hard`.
   Structural discipline, enforced by git, not by anyone's good intentions.
3. **Written memory.** A session does not remember card 3 at card 12, nor last
   night at all. Cards, delivered-probe replay, learned skills and hints are
   the loop's memory. Files, in git.
4. **A judge from another family.** Not because models lie, but because they
   have blind spots, and a reviewer sharing the maker's idiom finds nothing.

**What is scaffolding for a weak executor**, useful when your maker cannot be
trusted to verify its own work, unnecessary friction when it can:

- mandatory PROBE lines on every card,
- probe linting, discriminance checks, AUTODONE and its guards,
- prescribing HOW to verify rather than WHAT must be true.

A reasoning agent derives the verification itself, and does it better: given
"an aborted preview must not be overwritten by a late response", it reads the
code, finds the token that guards it, and reports with line numbers. A
`rg` probe would only have proved that an identifier exists somewhere.

**Where probes still earn their place**: as MEMORY, not as judgment. A probe
written for a defect that cost you dearly becomes a regression test replayed
on every future card (`law/regression-probes.sh`). That is worth writing. A
probe written to satisfy a form is not: measured on this very project, 22 of
166 replayed probes had gone false, most of them because they froze an
implementation the product later improved.

So: describe WHAT must be true, let the agent decide HOW to check it, run the
gates yourself, and write down only what must outlive the session.

## The ten rules

Still true regardless of maker or mode:

1. **The gate decides, never the maker's claim.** Run the commands.
2. **Atomic or nothing.** One commit, or a full reset. Never half-applied work.
3. **State WHAT must be true.** If you also pin HOW to verify it, make sure
   that check fails today, or it proves nothing.
4. **A repair card describes an OBSERVED defect.** If its checks already pass,
   the checks are wrong, not the defect gone.
5. **Judge and maker from different families.** A same-family review is worse
   than none: it manufactures confidence.
6. **A constated regression outranks any new feature.**
7. **Per-card gates do not see assembly breakage.** Run the full suite
   regularly and always before a merge, on a quiet machine.
8. **Infra failure is never the card's fault.** Overload, network, quota:
   pause and retry, never blame, never escalate on it.
9. **Reap what you spawn**, including the maker process itself: a maker whose
   driver died keeps writing into the worktree with nobody left to judge it.
10. **The owner launches and the owner merges.** Supervise. An anomaly caught
    by a safety net is still an anomaly: diagnose it now.

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

**A card IS a goal.** That is the shortest way to understand this skill.

All three agents ship a persistent-goal feature: Claude Code `/goal`, Codex
`thread_goals`, Hermes `goals.py` (which calls itself "the Ralph loop"). Each
holds an objective across turns and re-judges it until satisfied. A card holds
exactly the same thing, on a better substrate:

| | Native goal | A card |
| --- | --- | --- |
| Where it lives | a local DB (SQLite, SessionDB keyed by session id) | a markdown file, versioned in git |
| Survives | process death, if something resumes the session | reboot, machine change, being read by any tool |
| Stop condition | a model asked "is this satisfied?" | PROBES: commands that exit 0 or do not |
| Portability | tied to one CLI and its store | any agent can read a markdown file |
| Reviewable | opaque | diffable, reviewable, commentable |

So this is not an alternative to goal-oriented work, it IS goal-oriented work,
with the goal written where it cannot be lost and a stop condition that cannot
be talked into passing.

### Two ways to run the same thing

**Driver mode** (`law/loop-overnight.sh`): a headless process picks the next
card, spawns a fresh agent session for it, runs the gates, commits or resets.
Survives session death; a launchd/cron resurrector restarts it if it dies.

**Native mode**: an agent does the same loop itself, using a goal to hold the
intent and a SUB-AGENT per card to keep contexts isolated:

```
/goal Work the loop on this repo: take the highest-priority card from
      loop/state/queue, execute it in a sub-agent, run the gates, commit if
      green else git reset --hard, repeat until `bash loop/verify.sh` exits 0
      and no P0 card remains.
```

The sub-agent is what makes this viable: each card gets its own context and
throws it away, which is exactly what the driver achieves by spawning a fresh
CLI session per card.

Both modes need a system-level restarter to survive a machine reboot (launchd,
systemd, cron); neither is magic there. Hermes even ships a cron for it, and
the driver has a resurrector for the same reason.

Choose driver mode for long unattended nights, budget discipline and the fact
that a shell script cannot talk itself into accepting bad work. Choose native
mode for short supervised sessions, exploration, or when you want to start
without installing anything. The doctrine is identical in both: gates decide,
green is a commit, red is a reset, the owner merges.

### Writing the stop condition

Whatever mode you use, never let the stop condition be an opinion ("until the
feature works well"). Point it at something that exits 0: `verify.sh`, a
probe, a queue count, a commit in history. Note the wording each agent nudges
you toward: Claude Code says "keep working until the condition is met" (it
asks for a condition), Codex says "set a goal to keep pursuing" (it asks for
an intent). On Codex especially, write the checkable criterion yourself, or
the judge quietly falls back to opinion.

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
