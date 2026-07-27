#!/usr/bin/env bash
# init-loop.sh, scaffold the loop into the current git repository.
# Run from the target repo root:  bash <skill-dir>/scripts/init-loop.sh
# Creates loop/ with the law scripts (vendored, the project stays autonomous),
# a stack.sh pre-filled by stack detection, and an example card.
set -u
SKILL_SCRIPTS="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(pwd)"
git rev-parse --git-dir >/dev/null 2>&1 || { echo "run me from the root of a git repository"; exit 1; }
[ -d loop ] && { echo "loop/ already exists here, refusing to overwrite"; exit 1; }

mkdir -p loop/tasks
cp "$SKILL_SCRIPTS/loop.sh" "$SKILL_SCRIPTS/lib.sh" "$SKILL_SCRIPTS/probe-lint.sh" "$SKILL_SCRIPTS/verify.sh" loop/
chmod +x loop/*.sh

# ---------- stack detection (best effort, edit the result) ----------
GATES=""; INSTALL=""; SENTINEL=""; MANIFEST=""; LOCKSYNC=""; BRIEF_HINT=""
if [ -f package.json ]; then
  GATES="  'npm run build --if-present'\n  'npm test --if-present'"
  INSTALL="npm ci --no-audit --no-fund"; SENTINEL="node_modules"
  MANIFEST="package.json"; LOCKSYNC="npm install --package-lock-only --no-audit --no-fund"
  BRIEF_HINT="Node project"
fi
if [ -f pom.xml ]; then
  MVN="./mvnw"; [ -x ./mvnw ] || MVN="mvn"
  GATES="${GATES:+$GATES\n}  '$MVN -q test'"
  BRIEF_HINT="${BRIEF_HINT:+$BRIEF_HINT + }Maven project"
fi
if [ -f build.gradle ] || [ -f build.gradle.kts ]; then
  GATES="${GATES:+$GATES\n}  './gradlew test'"
  BRIEF_HINT="${BRIEF_HINT:+$BRIEF_HINT + }Gradle project"
fi
if [ -f Cargo.toml ]; then
  GATES="${GATES:+$GATES\n}  'cargo build'\n  'cargo test'"
  BRIEF_HINT="${BRIEF_HINT:+$BRIEF_HINT + }Rust project"
fi
if [ -f go.mod ]; then
  GATES="${GATES:+$GATES\n}  'go build ./...'\n  'go test ./...'"
  BRIEF_HINT="${BRIEF_HINT:+$BRIEF_HINT + }Go project"
fi
if [ -f pyproject.toml ] || [ -f setup.py ]; then
  GATES="${GATES:+$GATES\n}  'python -m pytest -q'"
  BRIEF_HINT="${BRIEF_HINT:+$BRIEF_HINT + }Python project"
fi
[ -z "$GATES" ] && GATES="  'echo EDIT-ME: add your build and test commands && false'"

# ---------- stack.sh ----------
cat > loop/stack.sh <<EOF
#!/usr/bin/env bash
# Stack contract: the ONE file that adapts the loop to this project.
# The law (loop.sh) never hardcodes stack commands. Spec: references/stack-contract.md.

STACK_NAME="$(basename "$ROOT")"

# --- maker agent: claude | codex | custom ---
LOOP_AGENT=claude
LOOP_MODEL=""                  # optional model override
LOOP_ESCALATION_MODEL=""       # optional stronger model for retries (zz-E- cards)
LOOP_CHECKER=auto              # independent reviewer: auto picks the OTHER family
# custom agent example (Hermes or any CLI), used when LOOP_AGENT=custom:
# LOOP_MAKER_TEMPLATE='hermes -z "\$(cat {PROMPT_FILE})"'

# --- gates: the verdict. Must pass on the untouched tree. Mock external services. ---
GATE_CMDS=(
$(printf "$GATES")
)

# --- full runtime suite (optional): run at close and for 00-E2E repair cards ---
E2E_CMD=''
# Only if E2E serves a BUILT artifact (stale dist = phantom failures):
E2E_BUILD_ARTIFACT=''   # e.g. front/dist/index.html
E2E_BUILD_SRC=''        # e.g. front/src
E2E_PREBUILD_CMD=''     # e.g. cd front && npx ng build

# --- install and lock discipline ---
STACK_INSTALL_CMD='${INSTALL}'
STACK_INSTALL_SENTINEL='${SENTINEL}'
STACK_LOCK_MANIFEST='${MANIFEST}'
STACK_LOCK_SYNC_CMD='${LOCKSYNC}'

# --- one paragraph injected into every maker prompt: contracts, conventions, traps ---
STACK_BRIEF='${BRIEF_HINT:-EDIT ME}: describe layout, conventions, and the traps a
newcomer would hit. This is the highest-leverage paragraph of the loop.'
EOF

# ---------- example card ----------
cat > loop/tasks/10-example-card.md <<'EOF'
# Example card, replace me

SCOPE: full
VALUE: P2

USE CASE:
One observable capability, in product language. Delete this card once you have
written real ones (read references/card-format.md in the skill first).

DONE WHEN:
- An observable criterion a human can check on the running app
- Tests prove it automatically, with external services MOCKED

PROBE: rg -q "a-token-that-does-not-exist-yet" src
PROBE: test -f a/file/the/work/will/create
EOF

# ---------- gitignore ----------
{ echo "loop/state/"; echo "loop/wip/"; echo "loop/logs/"; echo "loop/lot-gen/"; echo "loop/STOP"; } >> .gitignore

cat <<EOF

Loop scaffolded.

Next steps:
  1. Edit loop/stack.sh (agent, gates, STACK_BRIEF). Gates must be green on a clean tree.
  2. Write real cards in loop/tasks/ (spec: references/card-format.md in the skill).
  3. Lint them:        bash loop/probe-lint.sh loop/tasks/*.md
  4. Test the wiring:  LOOP_DRY_RUN=1 bash loop/loop.sh 5m
  5. First real run:   bash loop/loop.sh 1h    (supervised: tail -f loop/logs/run-*.log)
  6. Verify then merge yourself: bash loop/verify.sh --e2e && git merge --no-ff loop/work

Doctrine: no run without the owner's order, supervise every run, the owner merges.
EOF
