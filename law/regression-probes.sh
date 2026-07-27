#!/usr/bin/env bash
# regression-probes.sh, the cumulative gate: replay the probes of EVERY card
# already delivered, and fail if one of them broke.
#
# WHY: a card's probes are checked once, at its own cycle, and never again. A
# card that went green at cycle 3 can be silently broken at cycle 12 by an
# unrelated change, and nothing notices until the runtime suite runs (or ever,
# if the project has none). Every delivered probe is a free regression test:
# this replays them all.
#
# Usage:  bash loop/regression-probes.sh [worktree]     (default: repo root)
# Exit:   0 = no regression, 1 = at least one delivered probe now fails.
#
# Wire it as an extra gate in stack.sh, for example:
#   GATE_BACK_CMD='./mvnw -q test && bash loop/regression-probes.sh'
# or run it standalone before a merge.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1

# Source of delivered cards: GIT HISTORY, not loop/state/done. The state dir is
# wiped at every run start, so it only knows this run; history knows every card
# whose gate ever passed ("feat: <card> [loop"). That is the honest perimeter.
BASE="${REGRESSION_BASE:-HEAD}"
DELIVERED="$(git log --format=%s "$BASE" 2>/dev/null | sed -n 's/^feat: \(.*\) \[loop.*/\1/p' | sort -u)"
[ -n "$DELIVERED" ] || { echo "[regression] aucune carte livree dans l'historique, rien a rejouer"; exit 0; }

# Probes deliberately skipped: they are already the gates themselves (a full
# build or test run per card would make this gate quadratic), or they belong to
# the runtime phase (ports, long timeouts).
skip_probe(){
  case "$1" in
    *"playwright test"*|*"loop/e2e.sh"*|*"loop/verify.sh"*) return 0 ;;
    *"mvnw"*|*"gradlew"*|*"ng build"*|*"npm run build"*|*"npm test"*|*"cargo build"*|*"cargo test"*|*"go build"*|*"go test"*|*pytest*) return 0 ;;
  esac
  return 1
}

TOTAL=0; RAN=0; BROKEN=0; BROKEN_LIST=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  card=""
  for d in loop/state/done loop/tasks loop/archive/cartes-perimees; do
    [ -f "$d/$name.md" ] && { card="$d/$name.md"; break; }
  done
  [ -n "$card" ] || continue
  while IFS= read -r line; do
    p="${line#PROBE: }"; p="${p#\`}"; p="${p%\`}"
    [ -z "$p" ] && continue
    TOTAL=$(( TOTAL + 1 ))
    skip_probe "$p" && continue
    # prose probes never were executable: not a regression, just noise
    printf '%s' "$p" | grep -qiE '^ *(verifier|v\xc3\xa9rifier|verify|check|ensure|confirm|cliquer|ouvrir)' && continue
    RAN=$(( RAN + 1 ))
    if ! ( timeout "${REGRESSION_PROBE_TIMEOUT:-20}" bash -c "$p" ) >/dev/null 2>&1; then
      BROKEN=$(( BROKEN + 1 ))
      BROKEN_LIST="$BROKEN_LIST
  [$name] $p"
    fi
  done < <(grep '^PROBE: ' "$card" 2>/dev/null)
done <<< "$DELIVERED"

echo "[regression] $RAN probes rejouees sur $TOTAL declarees ($(( TOTAL - RAN )) sautees: gates et e2e)"
if [ "$BROKEN" -gt 0 ]; then
  echo "[regression] $BROKEN REGRESSION(S): une carte livree ne tient plus sa promesse"
  printf '%s\n' "$BROKEN_LIST"
  echo "[regression] ROUGE. Soit le code a regresse, soit la probe etait mensongere des l'origine: tranchez, ne supprimez pas la probe par confort."
  exit 1
fi
echo "[regression] VERT: toutes les promesses deja livrees tiennent encore"
exit 0
