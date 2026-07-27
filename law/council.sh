#!/usr/bin/env bash
# v6.46: interrupteur maitre (release-smoke et runs de consommation pure: zero LLM)
[ "${LOOP_COUNCIL:-1}" = 1 ] || { echo "[council] desactive (LOOP_COUNCIL=0)"; exit 0; }
PROJECT_DOMAIN="${PROJECT_DOMAIN:-}"; [ -f loop/stack.sh ] && . loop/stack.sh 2>/dev/null
# v6.1 THE COUNCIL. Convened when runtime fixing is exhausted (a lot's findings survived
# 2 fix generations): the question is no longer "retry harder" but "which approach is
# right". The council rules the way a good architect would: three explicit lenses
# (product / engineering / completeness), optional state-of-the-art web evidence, then a
# DECISION recorded in loop/DECISIONS.md.
#   JUDGMENT  class: resolvable by expertise+evidence, the ruling is authoritative.
#   PREFERENCE class: the principal's call really, BUT the loop does not block: it
#     proceeds on the completeness-preserving default, marked OVERTURNABLE, and the
#     morning review can reverse it (disagree-and-commit with an audit trail).
# Either class may emit a DIRECTIVE: a final council-directed fix card (00-F3-, one shot,
# never re-councilled). Usage: council.sh <lot-id> <residual-findings-file>
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
LOTID="${1:?usage: council.sh <lot-id> <findings-file>}"
FINDINGS_FILE="${2:?usage: council.sh <lot-id> <findings-file>}"
[ -s "$FINDINGS_FILE" ] || { echo "[council] no findings, nothing to rule on"; exit 0; }
LEDGER="loop/DECISIONS.md"
export PATH="$HOME/.local/bin:$PATH"

# --- optional state-of-the-art evidence (hermes web toolset; graceful skip) ---
WEB_EVIDENCE=""
if [ "${LOOP_COUNCIL_WEB:-1}" = 1 ]; then
  TOPIC="$(head -3 "$FINDINGS_FILE" | tr '\n' ' ' | head -c 200)"
  WEB_EVIDENCE="$(timeout 180 hermes -t web -z "Research briefly (5 bullet points max, cite sources): current best practice relevant to this software design question: $TOPIC" --cli 2>/dev/null | tail -c 2000)"
  [ -n "$WEB_EVIDENCE" ] && echo "[council] web evidence gathered ($(printf '%s' "$WEB_EVIDENCE" | wc -c | tr -d ' ') chars)"
fi

CARDS_CTX="$(for c in loop/tasks/*.md; do sed -n '1,3p' "$c"; echo; done | head -c 4000)"

CP="You are THE COUNCIL of an autonomous coding loop building ${PROJECT_DOMAIN:-a software project}
application (the cahier des
charges lives in docs/). A lot of shipped, gate-green changes was reviewed; its findings
survived two fix attempts. Runtime retry is over: the open question is an APPROACH or
DESIGN question. Rule on it as three experts in one:
1. PRODUCT lens: what serves the end users' real workflow.
2. ENGINEERING lens: soundness, simplicity, reversibility of each option.
3. COMPLETENESS lens: what best advances the WHOLE app toward the cahier des charges,
   an imperfect-but-complete feature beats a perfect fragment.
Read the repo for context as needed. Decide, do not hedge. If the question is truly the
principal's preference (product scope, external contracts, demo standards), still choose
the completeness-preserving DEFAULT and mark the class PREFERENCE.

## THE SURVIVING FINDINGS (lot $LOTID)
$(cat "$FINDINGS_FILE")

## STATE-OF-THE-ART EVIDENCE (may be empty)
$WEB_EVIDENCE

## THE APP'S CARDS (context)
$CARDS_CTX

Output EXACTLY these blocks:
===DECISION===
QUESTION: <the real underlying question, one line>
CHOSEN: <your ruling, one line>
CLASS: JUDGMENT or PREFERENCE
RATIONALE: <3-6 lines citing the lenses and evidence>
ALTERNATIVES: <the viable options not chosen, one line each>
REVERSE-BY: <concretely how a human overturns this later>
===END===
===DIRECTIVE===
<a complete fix card body implementing the CHOSEN ruling: USE CASE / CONTEXT / DONE WHEN
(max 3 bullets) / SCOPE: full / one PROBE per DONE WHEN bullet>
===END==="

# Chair: frontier judgment for a RARE event (once a night at most), so use the strongest
# available. LOOP_COUNCIL_CHAIR=codex (default, headless-proven) | claude (claude -p).
# Chair failure falls through: claude -> codex -> findings stay in morning proposals.
OUT=""
if [ "${LOOP_COUNCIL_CHAIR:-codex}" = "claude" ] && command -v claude >/dev/null 2>&1; then
  OUT="$(timeout 420 claude -p "$CP" --output-format text 2>/dev/null)"
  [ -n "$OUT" ] && echo "[council] chair: claude"
fi
if [ -z "$OUT" ]; then
  OUT="$(timeout 420 env PATH="$HOME/.sdkman/candidates/java/current/bin:$PATH" JAVA_HOME="$HOME/.sdkman/candidates/java/current" \
    codex exec --sandbox workspace-write --skip-git-repo-check "$CP" 2>/dev/null)"
  [ -n "$OUT" ] && echo "[council] chair: codex"
fi
[ -n "$OUT" ] || { echo "[council] no chair available, findings stay in proposals for the morning"; exit 0; }

DECISION="$(printf '%s\n' "$OUT" | awk '/^===DECISION===$/{f=1;next} /^===END===$/{f=0} f')"
DIRECTIVE="$(printf '%s\n' "$OUT" | awk '/^===DIRECTIVE===$/{f=1;next} /^===END===$/{f=0} f')"
[ -n "$DECISION" ] || { echo "[council] no parseable decision, findings stay in proposals"; exit 0; }

CLASS="$(printf '%s\n' "$DECISION" | grep -m1 '^CLASS:' | awk '{print $2}')"
CHOSEN="$(printf '%s\n' "$DECISION" | grep -m1 '^CHOSEN:' | cut -d: -f2- | head -c 160)"

# --- ledger (committed audit trail; the morning review reads this) ---
{ echo
  echo "## $(date '+%Y-%m-%d %H:%M'), lot $LOTID ${CLASS:-JUDGMENT}$( [ "$CLASS" = "PREFERENCE" ] && echo ', OVERTURNABLE' )"
  printf '%s\n' "$DECISION"
} >> "$LEDGER"
echo "[council] ruled on lot $LOTID (${CLASS:-JUDGMENT}):$CHOSEN"

# --- directive -> final council-directed fix card (one shot, never re-councilled) ---
if [ -n "$DIRECTIVE" ] && [ -d loop/state/queue ]; then
  FIX="loop/state/queue/00-F3-$LOTID-council.md"
  { echo "# Council-directed fix for lot $LOTID (FINAL generation)"
    echo
    printf '%s\n' "$DIRECTIVE"
    echo
    echo "COUNCIL RULING: $CHOSEN"
  } > "$FIX"
  echo "[council] directive queued: $(basename "$FIX")"
fi
git add "$LEDGER" 2>/dev/null
git -c user.name="loop-council" -c user.email="loop@local" commit -q -m "council: decision on lot $LOTID (${CLASS:-JUDGMENT}) [loop]" 2>/dev/null || true
exit 0
