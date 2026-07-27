# The stack contract: loop/stack.sh

One file adapts the loop to any project. The law sources it and never
hardcodes a stack command, a directory, a port or a project name anywhere
else. A missing or partial stack.sh must never crash a run: every variable
has a safe default (usually "feature off").

## Variables

### Identity and agent

```bash
STACK_NAME="my-project"          # informational, appears in reports
LOOP_AGENT=claude                # claude | codex | custom
LOOP_CHECKER=auto                # auto | off | claude | codex
# Optional knobs: set them with a VALUE or leave them commented out. Never
# write an empty assignment: the contract is sourced after env init, so
# LOOP_MODEL="" would silently erase an environment override.
# LOOP_MODEL='claude-opus-5'         # model override for the maker
# LOOP_ESCALATION_MODEL='claude-x'   # stronger model for zz-E- retries
# LOOP_MAKER_TEMPLATE='...'          # custom agents only, see below
```

Presets executed with the WORKTREE as cwd, prompt written to a temp file:

- `claude`: `claude --dangerously-skip-permissions [--model $LOOP_MODEL] -p "$(cat PROMPT)"`
- `codex`: `codex exec --sandbox workspace-write --skip-git-repo-check [-m $LOOP_MODEL] "$(cat PROMPT)"`
  (the prompt is UTF-8 sanitized first, the codex CLI rejects invalid UTF-8)
- `custom`: your template, with `{PROMPT_FILE}` replaced by the prompt path.
  Hermes example: `LOOP_MAKER_TEMPLATE='hermes -z "$(cat {PROMPT_FILE})"'`

**Warning on the claude preset.** `--dangerously-skip-permissions` gives the
agent free file and shell access. The loop's containment is the disposable
worktree plus the hard reset on red, and that has proven sufficient for
project work, but do not point the loop at a checkout containing secrets, and
never run it outside a worktree. If you tighten to
`--permission-mode acceptEdits`, know that shell-based build steps will
prompt and a headless run will hang: test your choice with a short
supervised run first.

### Gates (the verdict)

```bash
GATE_CMDS=(
  'cd frontend && npx ng build'
  'cd backend && ./mvnw -q test'
)
E2E_CMD=''                       # full runtime suite, run at close and for 00-E2E cards
E2E_BUILD_ARTIFACT=''            # only if E2E serves a built artifact (dist/index.html)
E2E_BUILD_SRC=''                 # source dir to compare freshness against
E2E_PREBUILD_CMD=''              # rebuild command when artifact is stale
```

Rules learned:

- Gates run on the UNTOUCHED tree at preflight and must pass there, else the
  run refuses to start (a red base makes every card verdict meaningless).
- Gates must not depend on external services being up. Mock them in tests.
- The freshness trio exists because a suite serving a stale dist produced 18
  phantom failures against a week-old scaffold. Dev-server suites (compile
  from source) leave the trio empty.

### Install and lock discipline

```bash
STACK_INSTALL_CMD='cd frontend && npm ci --no-audit --no-fund'
STACK_INSTALL_SENTINEL='frontend/node_modules'   # present = skip install
STACK_LOCK_MANIFEST='frontend/package.json'
STACK_LOCK_SYNC_CMD='cd frontend && npm install --package-lock-only'
```

`npm ci` style installs fail loudly when manifest and lock diverge. That is
wanted: a maker that added a dependency without regenerating the lock killed
the NEXT run's preflight, silently, until the install lost its `--silent`.
The law runs LOCK_SYNC when a green touched the manifest.

### Prompt brief

```bash
STACK_BRIEF='Angular 21 front in frontend/ (signals, zoneless), Spring Boot
3.5 back in backend/ (Java 21). Auth is mocked in tests. Conventions: ...'
```

One paragraph injected into every maker prompt. Contracts, conventions,
traps. This is the highest-leverage text you will write: every card benefits.

### Tunables (defaults shown)

```bash
LOOP_BASE=""            # base branch, default: current branch at first run
LOOP_MIN_REMAINING=1200 # stop picking when less than 20 min remain
LOOP_MAKER_TIMEOUT=2400 # seconds per maker session
LOOP_GATE_TIMEOUT=1800  # seconds per gate command
LOOP_PROBE_TIMEOUT=30   # seconds per probe
LOOP_MAXGEN=2           # fix-lot generation cap per base
LOOP_MAX_ATTEMPTS=2     # tries per card before parked (1 normal + 1 escalated)
```

## What must NOT be in stack.sh

Law logic. If you find yourself adding retry rules, probe parsing or failure
classification here, you are forking the law: put it in loop.sh generically,
with the incident documented, so every project sharing the law benefits.
