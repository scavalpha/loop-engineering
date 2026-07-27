# loop-engineering

An installable skill that teaches any coding agent (Claude Code, Codex, or a
custom CLI such as Hermes) to build and operate an autonomous engineering
loop on a local git project: card-based work units, a deterministic bash law,
gates as the only verdict, atomic commit or reset, independent review, and a
supervision doctrine.

Distilled from 80+ hardening revisions of a production loop that built real
banking applications overnight. Every rule carries the incident that created
it.

## Install

### Claude Code

```bash
git clone <this-repo> ~/dev/loop-engineering
ln -s ~/dev/loop-engineering ~/.claude/skills/loop-engineering
```

Then in any project: ask Claude "set up a loop on this repo" (the skill
triggers on loop engineering topics), or run the scaffolder directly:

```bash
cd /path/to/your/project
bash ~/dev/loop-engineering/scripts/init-loop.sh
```

### Codex

Codex reads `AGENTS.md`. Add one line to `~/.codex/AGENTS.md` (global) or to
the project's `AGENTS.md`:

```
For anything about engineering loops (setup, cards, runs, supervision), read
~/dev/loop-engineering/SKILL.md and follow it.
```

### Hermes or any other agent CLI

The skill is plain markdown plus bash: point your agent at `SKILL.md`. To use
your CLI as the loop's MAKER, set in `loop/stack.sh`:

```bash
LOOP_AGENT=custom
LOOP_MAKER_TEMPLATE='hermes -z "$(cat {PROMPT_FILE})"'
```

Any command template works as long as it reads the prompt and edits files in
the current directory.

## Use on a project

```bash
cd /path/to/project
bash ~/dev/loop-engineering/scripts/init-loop.sh   # scaffolds loop/ (vendored, autonomous)
$EDITOR loop/stack.sh                              # agent, gates, brief
$EDITOR loop/tasks/                                # write real cards
bash loop/probe-lint.sh loop/tasks/*.md            # lint before running
LOOP_DRY_RUN=1 bash loop/loop.sh 5m                # wiring test
bash loop/loop.sh 1h                               # first supervised run
bash loop/verify.sh --e2e                          # independent verification
git merge --no-ff loop/work                        # the OWNER merges
```

The scaffold vendors the law into the project (`loop/*.sh`), so teammates and
CI need nothing but the repo. Skill updates are re-vendored by copying the
scripts again.

## Layout

```
SKILL.md                       agent-facing instructions (any agent can read it)
references/doctrine.md         the laws and the incidents behind them
references/card-format.md      cards and probes that cannot lie
references/stack-contract.md   the one file adapting the loop to any stack
references/supervision.md      launch, monitor, failure classes, close checklist
scripts/init-loop.sh           scaffolder
scripts/loop.sh                the law (driver)
scripts/lib.sh                 shared functions
scripts/probe-lint.sh          card linter
scripts/verify.sh              gates by hand, same as the law
```

## Non-negotiables

1. The gate decides, never the maker.
2. Green is a commit, red is a reset. Nothing in between.
3. Probes are AND, executable, discriminant. Repair cards never auto-complete.
4. Maker and reviewer come from different model families.
5. Infra failure (overload, network, quota) never blames the card.
6. Full e2e before any merge, on a quiet machine, run by you.
7. No run without the owner's explicit order. Supervise. The owner merges.

## Relation to goal modes

Claude Code `/goal`, Codex goals and Hermes goal mode are the same thing: a
persistent objective re-judged by a MODEL until it says done (the "Ralph
loop"). This skill makes compilers, tests and probes the judge instead, with
atomic commit-or-reset per card. They compose rather than compete: give the
goal a machine-checkable stop condition and let the loop supply the verdict.

    /goal keep running loop cycles until `bash loop/verify.sh --e2e` exits 0
          and no P0 card remains in loop/state/queue

See the "Relation to goal modes" section of SKILL.md.
