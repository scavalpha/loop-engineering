#!/usr/bin/env bash
# init-loop.sh, install the shared law into the current git repository.
# Run from the target repo root:  bash <skill-dir>/scripts/init-loop.sh
#
# Vendors the full law into loop/ (the project stays autonomous afterwards),
# writes a stack.sh SKELETON pre-filled from stack detection, and creates the
# spec file the cartographer reads. It deliberately does NOT guess your gates:
# an agent following SKILL.md interviews you and fills them in.
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
git rev-parse --git-dir >/dev/null 2>&1 || { echo "run me from the root of a git repository"; exit 1; }
[ -d loop ] && { echo "loop/ already exists here. To update the law: bash $SKILL/scripts/sync-law.sh"; exit 1; }

mkdir -p loop/tasks loop/tests docs
cp "$SKILL"/law/*.sh "$SKILL"/law/*.mjs "$SKILL"/law/*.md loop/ 2>/dev/null
cp "$SKILL"/law/LAW-VERSION loop/ 2>/dev/null
cp "$SKILL"/law/tests/*.sh loop/tests/ 2>/dev/null
chmod +x loop/*.sh loop/tests/*.sh 2>/dev/null

# ---------- detection (a hint for the interview, never a silent decision) ----------
AGENTS=""; for c in claude codex hermes; do command -v "$c" >/dev/null 2>&1 && AGENTS="$AGENTS $c"; done
STACKS=""
[ -f package.json ]   && STACKS="$STACKS node"
[ -f pom.xml ]        && STACKS="$STACKS maven"
[ -f build.gradle ] || [ -f build.gradle.kts ] && STACKS="$STACKS gradle"
[ -f Cargo.toml ]     && STACKS="$STACKS rust"
[ -f go.mod ]         && STACKS="$STACKS go"
[ -f pyproject.toml ] || [ -f setup.py ] && STACKS="$STACKS python"
[ -f pubspec.yaml ]   && STACKS="$STACKS flutter"
ls *.xcodeproj >/dev/null 2>&1 && STACKS="$STACKS xcode"

# ---------- contract skeleton ----------
cat > loop/stack.sh <<EOF
#!/usr/bin/env bash
# STACK CONTRACT: the ONE file that adapts the shared law to THIS project.
# The law in loop/*.sh is generic and must never be edited here.
# Full spec: loop/STACK-CONTRACT.md   Guide: <skill>/references/stack-contract.md
# Detected on install: agents:${AGENTS:- none} | stack:${STACKS:- unknown}

STACK_NAME="$(basename "$(pwd)")"
PROJECT_DOMAIN="EDIT ME: one line describing what this product IS, in product words"
ARCH_PROFILE="web-fullstack"      # web-fullstack | api-only | mobile | lib | cli

# --- casting: which agent plays which role (see references/agents.md) ---
LOOP_MAKER_KIND=claude            # claude | codex | hermes
LOOP_MAKER=""                     # model id, empty = the CLI default
LOOP_LOT_CHAIR=codex              # the CHECKER: must be a DIFFERENT family than the maker
LOOP_NO_LOCAL_LLM=1               # 1 = frontier casting, no local model needed

# --- where the code lives ---
BACK_DIR="backend"
FRONT_DIR="frontend"

# --- the gates: THE verdict. Must be green on an untouched tree. ---
GATE_FRONT_CMD='EDIT ME: your front build, e.g. npx ng build'
GATE_BACK_CMD='EDIT ME: your back tests, e.g. ./mvnw -q test'

# --- install (optional) ---
STACK_INSTALL_CMD=''
STACK_INSTALL_SENTINEL=''

# --- environment this project actually needs (leave off if it needs none) ---
DB_REQUIRED=0
# DB_HEALTH_CMD='pg_isready -h localhost -p 5432'

# --- runtime gate (optional but this is what makes a loop trustworthy) ---
E2E_SENTINEL=''                   # e.g. frontend/node_modules/@playwright
# E2E_FRONT_PORT='4318'

# --- injected into EVERY maker prompt: conventions, contracts, traps ---
STACK_BRIEF='EDIT ME: frameworks and versions, directory layout, naming and
language conventions, how tests are run, what must never be touched. This is
the highest-leverage paragraph in the whole setup.'
EOF

# ---------- the spec the cartographer reads ----------
[ -f docs/domain-rules.md ] || cat > docs/domain-rules.md <<'EOF'
# Business rules and use cases

The cartographer compares THIS file to the code that actually exists, and
emits the next cards. Write rules and use cases, not tasks.

## Use cases
- UC1 ...: who does what, and what they see afterwards
- UC2 ...

## Rules
- A rule is a sentence that can be violated by code. "Prices are stored in
  cents, never floats" is a rule. "The app should be fast" is not.
EOF

{ echo "loop/state/"; echo "loop/wip/"; echo "loop/logs/"; echo "loop/lot-gen/"; echo "loop/STOP"; } >> .gitignore

cat <<EOF

Law installed (version $(cat loop/LAW-VERSION 2>/dev/null || echo '?')).
Detected: agents:${AGENTS:- NONE FOUND} | stack:${STACKS:- unknown}

Three files decide everything now:
  loop/stack.sh          how to build and test THIS project   <- fill it in
  docs/domain-rules.md   your spec, read by the cartographer  <- fill it in
  loop/tasks/*.md        cards (or let the cartographer write them)

Next: ask your coding agent to "set up the loop on this project". It will
interview you (maker, checker, project type, gates, runtime test) and fill
loop/stack.sh for you. Then:

  bash loop/verify.sh                 # gates must be GREEN on the clean tree
  bash loop/loop.sh 1h                # first run, short and supervised

Doctrine: no run without the owner's explicit order, supervise every run,
the owner merges.
EOF
