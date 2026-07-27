#!/usr/bin/env bash
# probe-lint.sh, advisory linter for cards. Catches the probe shapes that made
# real cards lie: OR-probes, always-true probes, prose probes, malformed
# commands, scenery probes on repair cards, missing VALUE.
#
# Usage: bash loop/probe-lint.sh loop/tasks/*.md
# Exit code: number of cards with at least one finding (0 = clean).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BAD=0
for f in "$@"; do
  [ -f "$f" ] || continue
  n="$(basename "$f" .md)"; findings=0
  say() { echo "[$n] $*"; findings=1; }

  # 1. at least one PROBE line
  if ! grep -q '^PROBE: ' "$f"; then
    say "no PROBE line: the card has no definition of done, it can neither AUTODONE nor prove itself"
  fi

  # 2. VALUE present (unprioritized fix cards sank below features and an e2e stayed red a whole run)
  grep -q '^VALUE:' "$f" || say "no VALUE line (P0..P3): defaults to P2, is that intended?"

  # 3. OR-probes: alternation in pattern or shell ||, true-before-the-work
  card_has_or_probes "$f" && say "OR-probe (| in pattern or || between commands): can be true before the work exists, AUTODONE will be refused but fix the card"

  # 4. always-true
  at="$(card_always_true_probes "$f")"
  [ -n "$at" ] && say "ALWAYS-TRUE probe (unconditional exit 0): $at"

  # 5. prose probes (stderr of card_probes)
  prose="$(card_probes "$f" 2>&1 >/dev/null)"
  [ -n "$prose" ] && say "$prose"

  # 6. malformed probes (rc>=2 on dry-run: can never turn green)
  mal="$(probe_dry_lint "$f" "$ROOT")"
  [ -n "$mal" ] && say "$mal"

  # 7. discriminance: probes that ALL pass today prove nothing about the work.
  #    Fatal on repair cards, a warning elsewhere.
  if run_probes "$f" "$ROOT" 15 2>/dev/null; then
    if is_repair_card "$n"; then
      say "REPAIR CARD whose probes all pass TODAY: the probes are scenery, the defect is still there. Require an artifact only the fix can produce."
    else
      say "note: all probes already pass, the card will AUTODONE at seed (fine if the feature landed, scenery if not)"
    fi
  fi

  [ "$findings" -eq 1 ] && BAD=$(( BAD + 1 )) || echo "[$n] ok"
done
exit "$BAD"
