#!/usr/bin/env bash
# verify-card.sh, the reasoning verdict FOR DRIVER MODE ONLY.
#
# READ THIS BEFORE USING IT: in agent mode you do not need this script. The
# whole thing is one instruction you can simply follow:
#
#   "Before calling a card green, have it verified by an agent of a DIFFERENT
#    family: it reads the card, the diff and the code, and answers whether each
#    requirement is genuinely met, with evidence. The build and tests were
#    already run by the gates, so it judges BEHAVIOUR, not compilation."
#
# This file exists because bash cannot read that instruction and act on it. It
# is a prosthesis for a driver, not the general solution. If you are a reasoning
# agent running the loop yourself, follow the instruction and delete this from
# your mental model.
#
# WHY: the driver is bash, it cannot reason, so historically every card had to
# carry PROBE lines. That produced more lies than it caught: probes that were
# true before the work existed, probes that froze an implementation the product
# later improved, and cards with no probe at all (every generated fix-lot)
# judged by nothing but "it still compiles".
#
# A card states WHAT must be true. An agent can read the card, read the diff,
# read the code and answer honestly. That is a better verdict than a grep, and
# it is what the maker's own family is NOT allowed to give (see LOOP_VERIFIER:
# use a different family than the maker whenever both are installed).
#
# Usage:  bash loop/verify-card.sh <card-file> <worktree> [base-ref]
# Exit:   0 = card satisfied, 1 = not satisfied, 3 = no verifier available (SKIP)
#
# The verdict is ADVISORY when it cannot run (exit 3): the gates still rule.
set -u
CARD="${1:?usage: verify-card.sh <card> <worktree> [base]}"
WT="${2:?}"; BASE="${3:-HEAD}"
[ -f "$CARD" ] || { echo "[verify-card] carte introuvable: $CARD"; exit 3; }

# Verifier family: prefer the OPPOSITE of the maker, a model reviewing its own
# idiom finds nothing. LOOP_VERIFIER=off disables the whole node.
V="${LOOP_VERIFIER:-auto}"
[ "$V" = off ] && { echo "[verify-card] desactive (LOOP_VERIFIER=off)"; exit 3; }
if [ "$V" = auto ]; then
  case "${LOOP_MAKER_KIND:-}" in
    claude) command -v codex  >/dev/null 2>&1 && V=codex  || V=claude ;;
    codex)  command -v claude >/dev/null 2>&1 && V=claude || V=codex ;;
    *)      command -v claude >/dev/null 2>&1 && V=claude || V=codex ;;
  esac
fi
command -v "$V" >/dev/null 2>&1 || { echo "[verify-card] aucun verificateur ($V absent)"; exit 3; }

DIFF="$(git -C "$WT" diff "$BASE" 2>/dev/null | head -c 60000)"
[ -n "$DIFF" ] || DIFF="$(git -C "$WT" diff 2>/dev/null | head -c 60000)"

P="$(mktemp)"
{ echo "You are the VERIFIER of an engineering loop. Decide whether the card below"
  echo "is REALLY satisfied by the work that was just done. You are not reviewing"
  echo "style or design: you are answering one question honestly."
  echo
  echo "IMPORTANT, what is NOT yours to judge: the build and the test suite have"
  echo "ALREADY been run and passed before you were called. Ignore any card"
  echo "requirement of the form \"it still builds\" or \"the tests pass\": treat"
  echo "those as met. You run read-only and cannot execute them, so judging them"
  echo "would only produce a false NOT-DONE. Judge the BEHAVIOUR the card asks for."
  echo
  echo "Method: read the card, read the diff, and READ THE ACTUAL CODE in the"
  echo "worktree if the diff is not enough ($WT). Check every requirement the card"
  echo "states. Do not accept an intention, a comment or a renamed variable as"
  echo "proof that a behaviour exists."
  echo
  echo "Answer in this exact shape:"
  echo "VERDICT: DONE      (every requirement of the card is genuinely met)"
  echo "VERDICT: NOT-DONE  (at least one is not)"
  echo "then one line per requirement: - <requirement>: met | NOT met, <evidence"
  echo "with file and line, or what is missing>."
  echo
  echo "Be strict and be honest. A card wrongly declared DONE ships a defect. A"
  echo "card wrongly declared NOT-DONE wastes a cycle. Both are real costs, so"
  echo "judge on evidence, never on impression."
  echo
  echo "## THE CARD"; cat "$CARD"
  echo; echo "## THE DIFF"; printf '%s\n' "$DIFF"
} > "$P"
# codex rejects non-UTF-8 arguments outright
iconv -f UTF-8 -t UTF-8 -c < "$P" > "$P.u" 2>/dev/null && mv "$P.u" "$P"

case "$V" in
  claude) OUT="$(cd "$WT" && timeout 420 claude -p "$(cat "$P")" --output-format text 2>/dev/null)" ;;
  codex)  OUT="$(cd "$WT" && timeout 420 codex exec --sandbox read-only --skip-git-repo-check "$(cat "$P")" 2>/dev/null)" ;;
esac
rm -f "$P"

[ -n "$OUT" ] || { echo "[verify-card] verificateur ($V) muet: verdict indisponible"; exit 3; }
printf '%s\n' "$OUT" | head -25

case "$(printf '%s' "$OUT" | grep -oiE 'VERDICT: *(DONE|NOT-DONE)' | tail -1 | tr '[:lower:]' '[:upper:]')" in
  *NOT-DONE*) echo "[verify-card] $V: NOT-DONE"; exit 1 ;;
  *DONE*)     echo "[verify-card] $V: DONE";     exit 0 ;;
  *) echo "[verify-card] $V n'a pas rendu de verdict lisible: indisponible"; exit 3 ;;
esac
