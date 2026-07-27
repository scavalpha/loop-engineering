#!/usr/bin/env bash
# loop.sh, the deterministic law of the engineering loop.
#
# A card is picked, a maker agent (claude | codex | custom) executes it inside a
# disposable worktree, then compilers, tests and probes judge. Green becomes one
# commit on the loop branch. Red becomes a hard reset with the attempt banked.
# The maker's opinion is never the verdict.
#
# Usage:   bash loop/loop.sh <duration> ;  duration = 45m | 2h | HH:MM
#          LOOP_DRY_RUN=1 bash loop/loop.sh 5m   (machinery test, maker is a no-op)
# Stop:    touch loop/STOP   (honored after the current cycle)
#
# Distilled from a production law hardened over 80+ revisions. Comments keep the
# incident behind each rule: a rule whose origin is forgotten gets deleted, and
# the incident comes back.
set -u

# ---------- locate ----------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
MAIN="$(cd "$SCRIPT_DIR/.." && pwd)"          # repo root (loop/ lives under it)
cd "$MAIN" || exit 1
git rev-parse --git-dir >/dev/null 2>&1 || { echo "not a git repo: $MAIN"; exit 1; }

# ---------- contract ----------
STACK_NAME="$(basename "$MAIN")"
LOOP_AGENT="${LOOP_AGENT:-claude}"; LOOP_MODEL="${LOOP_MODEL:-}"
LOOP_ESCALATION_MODEL="${LOOP_ESCALATION_MODEL:-}"
LOOP_CHECKER="${LOOP_CHECKER:-auto}"; LOOP_MAKER_TEMPLATE="${LOOP_MAKER_TEMPLATE:-}"
GATE_CMDS=(); E2E_CMD=""; STACK_BRIEF=""
E2E_BUILD_ARTIFACT=""; E2E_BUILD_SRC=""; E2E_PREBUILD_CMD=""
STACK_INSTALL_CMD=""; STACK_INSTALL_SENTINEL=""
STACK_LOCK_MANIFEST=""; STACK_LOCK_SYNC_CMD=""
LOOP_BASE="${LOOP_BASE:-}"
LOOP_MIN_REMAINING="${LOOP_MIN_REMAINING:-1200}"
LOOP_MAKER_TIMEOUT="${LOOP_MAKER_TIMEOUT:-2400}"
LOOP_GATE_TIMEOUT="${LOOP_GATE_TIMEOUT:-1800}"
LOOP_PROBE_TIMEOUT="${LOOP_PROBE_TIMEOUT:-30}"
LOOP_MAXGEN="${LOOP_MAXGEN:-2}"
LOOP_MAX_ATTEMPTS="${LOOP_MAX_ATTEMPTS:-2}"
[ -f loop/stack.sh ] && . loop/stack.sh
# dry-run is a wiring test: let short durations actually cycle
[ "${LOOP_DRY_RUN:-0}" = 1 ] && LOOP_MIN_REMAINING=60

DEADLINE="$(parse_deadline "${1:?usage: loop.sh <45m|2h|HH:MM>}")" || exit 1
RUN="$(date +%Y%m%d-%H%M%S)"
BR="loop/work"
WT="$(dirname "$MAIN")/$(basename "$MAIN")-loop"
mkdir -p loop/state/queue loop/state/done loop/state/failed loop/state/attempts \
         loop/wip loop/logs loop/lot-gen
REPORT="loop/state/report-$RUN.md"
RLOG="loop/logs/run-$RUN.log"
exec > >(tee -a "$RLOG") 2>&1
: > "$REPORT"
log "RUN $RUN  deadline $(date -r "$DEADLINE" '+%H:%M' 2>/dev/null || date -d "@$DEADLINE" '+%H:%M')  agent=$LOOP_AGENT${LOOP_MODEL:+/$LOOP_MODEL}  dry=${LOOP_DRY_RUN:-0}"

# ---------- maker ----------
maker_run() { # $1 = prompt file, $2 = model override (may be empty). cwd must be $WT.
  local pf="$1" model="${2:-$LOOP_MODEL}"
  [ "${LOOP_DRY_RUN:-0}" = 1 ] && { log "DRY maker (no-op)"; return 0; }
  sanitize_utf8 "$pf"
  case "$LOOP_AGENT" in
    claude)
      timeout "$LOOP_MAKER_TIMEOUT" claude --dangerously-skip-permissions \
        ${model:+--model "$model"} -p "$(cat "$pf")" ;;
    codex)
      timeout "$LOOP_MAKER_TIMEOUT" codex exec --sandbox workspace-write \
        --skip-git-repo-check ${model:+-m "$model"} "$(cat "$pf")" ;;
    custom)
      [ -n "$LOOP_MAKER_TEMPLATE" ] || { log "FATAL: LOOP_AGENT=custom needs LOOP_MAKER_TEMPLATE"; return 90; }
      timeout "$LOOP_MAKER_TIMEOUT" bash -c "${LOOP_MAKER_TEMPLATE//\{PROMPT_FILE\}/$pf}" ;;
    *) log "FATAL: unknown LOOP_AGENT=$LOOP_AGENT"; return 90 ;;
  esac
}
maker_ping() {
  [ "${LOOP_DRY_RUN:-0}" = 1 ] && return 0
  local pf; pf="$(mktemp)"; echo "Reply with the single word: pong" > "$pf"
  ( cd "$WT" && LOOP_MAKER_TIMEOUT=90 maker_run "$pf" "" ) >/dev/null 2>&1
}

# ---------- gates ----------
run_gates() { # $1 = extra gate (optional, used to append E2E for 00-E2E cards)
  local g rc
  for g in ${GATE_CMDS[@]+"${GATE_CMDS[@]}"} ${1:+"$1"}; do
    log "gate: $g"
    ( cd "$WT" && timeout "$LOOP_GATE_TIMEOUT" bash -c "$g" ) > /tmp/loop-gate.$$ 2>&1; rc=$?
    if [ "$rc" -ne 0 ]; then
      log "RED gate (rc=$rc): $g"; tail -15 /tmp/loop-gate.$$ | sed 's/^/    /'
      rm -f /tmp/loop-gate.$$; return 1
    fi
  done
  rm -f /tmp/loop-gate.$$ 2>/dev/null; return 0
}

# ---------- infra classification (never blame the card) ----------
OVERLOAD_N=0
classify_infra() { # $1 = maker output file. Prints class or nothing.
  local out="$1"
  if tail -20 "$out" 2>/dev/null | grep -qiE '\b529\b|overloaded|\b503\b|service unavailable'; then
    echo overloaded; return; fi
  if tail -20 "$out" 2>/dev/null | grep -qiE 'ECONNREFUSED|ENOTFOUND|ETIMEDOUT|network is unreachable' \
     && ! curl -sI --max-time 8 https://api.anthropic.com >/dev/null 2>&1; then
    echo network; return; fi
  if tail -20 "$out" 2>/dev/null | grep -qiE 'rate.?limit|too many requests|\btry again at\b|insufficient_quota|usage limit'; then
    echo quota; return; fi
}

# ---------- orphan reaping ----------
reap() { # kill every process pointing into the worktree, except agent CLIs and us.
  local pid cmd
  for pid in $(pgrep -f -- "$WT" 2>/dev/null); do
    [ "$pid" = "$$" ] && continue
    cmd="$(ps -o command= -p "$pid" 2>/dev/null)"
    case "$cmd" in *claude*|*codex*|*hermes*|*loop.sh*|"") continue ;; esac
    kill -9 "$pid" 2>/dev/null && log "reap orphan $pid: $(printf '%.60s' "$cmd")"
  done
  pkill -f 'headless_shell' 2>/dev/null
}

# ---------- worktree ----------
BASE="${LOOP_BASE:-$(git branch --show-current)}"
if [ -d "$WT/.git" ] || git -C "$WT" rev-parse --git-dir >/dev/null 2>&1; then
  log "worktree resume: $WT (branch $BR)"
  git -C "$WT" merge --no-edit "$BASE" >/dev/null 2>&1 || {
    log "REFUSE: base does not merge cleanly into $BR, resolve by hand"; exit 1; }
else
  git branch "$BR" "$BASE" 2>/dev/null
  git worktree add "$WT" "$BR" >/dev/null 2>&1 || { log "REFUSE: worktree add failed"; exit 1; }
  log "worktree created: $WT (branch $BR from $BASE)"
fi

# ---------- preflight ----------
if [ -n "$STACK_INSTALL_CMD" ] && [ -n "$STACK_INSTALL_SENTINEL" ] && [ ! -e "$WT/$STACK_INSTALL_SENTINEL" ]; then
  log "install deps..."
  ( cd "$WT" && bash -c "$STACK_INSTALL_CMD" ) || { log "REFUSE: install failed (lock desync? run STACK_LOCK_SYNC_CMD)"; exit 1; }
fi
run_gates || { log "REFUSE: gates red on the UNTOUCHED tree, a red base voids every verdict"; exit 1; }
maker_ping || { log "REFUSE: maker ($LOOP_AGENT) does not answer"; exit 1; }
log "preflight OK (gates green on clean tree, maker answers)"

# ---------- seed ----------
for f in loop/tasks/*.md; do
  [ -f "$f" ] || continue
  n="$(basename "$f" .md)"
  # dedup by history: the one honest exit for repair cards (green probes on a
  # repair card mean bad probes, so probes cannot retire them, only a commit can)
  if green_in_history "$n" "$WT"; then
    log "seed-dedup: $n already green in history"; continue
  fi
  cp "$f" "loop/state/queue/$n.md"
done
# lint at seed: malformed probes neutralized loudly, OR-probes flagged
for q in loop/state/queue/*.md; do
  [ -f "$q" ] || continue
  qn="$(basename "$q" .md)"
  probe_dry_lint "$q" "$WT" | sed "s/^/[lint $qn] /"
  card_has_or_probes "$q" && log "[lint $qn] OR-probe: AUTODONE forbidden, will go through maker + gates"
  at="$(card_always_true_probes "$q")" && [ -n "$at" ] && log "[lint $qn] ALWAYS-TRUE probe, fix the card: $at"
done
QN="$(ls loop/state/queue/*.md 2>/dev/null | wc -l | tr -d ' ')"
log "queue: $QN cards"

# ---------- pick ----------
pick_card() {
  local best="" bestkey="" f v k
  for f in loop/state/queue/*.md; do
    [ -f "$f" ] || continue
    v="$(card_value "$f")"
    k="$v/$(basename "$f")"
    if [ -z "$bestkey" ] || [[ "$k" < "$bestkey" ]]; then bestkey="$k"; best="$f"; fi
  done
  printf '%s' "$best"
}

# ---------- fix-lot (independent checker) ----------
checker_cli() {
  case "$LOOP_CHECKER" in
    off) return 1 ;;
    claude|codex) command -v "$LOOP_CHECKER" >/dev/null && echo "$LOOP_CHECKER" ;;
    auto)
      # opposite family of the maker: a judge from the maker's family finds nothing
      case "$LOOP_AGENT" in
        claude) command -v codex  >/dev/null && echo codex ;;
        codex)  command -v claude >/dev/null && echo claude ;;
        *)      command -v claude >/dev/null && echo claude || { command -v codex >/dev/null && echo codex; } ;;
      esac ;;
  esac
}
review_green() { # $1 = card name, $2 = commit sha
  local chair name="$1" sha="$2" pf out verdict findings base cf gen
  chair="$(checker_cli)" || return 0
  [ -z "$chair" ] && return 0
  pf="$(mktemp)"
  { echo "You are the independent reviewer of an engineering loop. The gates already"
    echo "guarantee this commit builds and passes tests. Look ONLY for integration"
    echo "defects: contract mismatches, broken flows, rules bypassed. Reply with"
    echo "VERDICT: PASS or VERDICT: FAIL, then one line per finding: - [file] problem."
    echo; echo "## COMMIT"; git -C "$WT" show --stat --format='%s' "$sha" | head -40
    echo; echo "## DIFF";   git -C "$WT" show --format='' "$sha" | head -c 30000
  } > "$pf"
  sanitize_utf8 "$pf"
  case "$chair" in
    codex)  out="$(timeout 420 codex exec --sandbox read-only --skip-git-repo-check "$(cat "$pf")" 2>/dev/null)" ;;
    claude) out="$(timeout 420 claude -p "$(cat "$pf")" 2>/dev/null)" ;;
  esac
  rm -f "$pf"
  verdict="$(printf '%s' "$out" | grep -oiE 'VERDICT: *(PASS|FAIL)' | tail -1 | grep -oiE 'PASS|FAIL' | tr '[:lower:]' '[:upper:]')"
  [ "$verdict" = FAIL ] || { log "review($chair): ${verdict:-no-verdict} on $name"; return 0; }
  findings="$(printf '%s' "$out" | grep -E '^ *- \[' | head -c 4000)"
  [ -n "$findings" ] || { log "review($chair): FAIL without findings, ignored (fail-closed on noise)"; return 0; }
  base="$(base_of "$name")"
  cf="loop/lot-gen/$base.count"                       # persisted in MAIN: survives worktree resets
  gen=$(( $(cat "$cf" 2>/dev/null || echo 0) + 1 )); echo "$gen" > "$cf"
  if [ "$gen" -gt "$LOOP_MAXGEN" ]; then
    log "review($chair): FAIL on $name but generation cap reached ($gen > $LOOP_MAXGEN): findings go to the report, no more fix cards for this base"
    { echo "## Findings beyond cap for $base (gen $gen)"; printf '%s\n' "$findings"; } >> "$REPORT"
    return 0
  fi
  local fix="loop/state/queue/00-F$gen-$base-fixes.md"
  { echo "# Fix lot $base, reviewer findings (generation $gen)"
    echo; echo "SCOPE: full"; echo "VALUE: P0"
    echo; echo "USE CASE:"
    echo "An independent reviewer inspected the shipped change ($name) and found the"
    echo "integration defects below. The code is committed and working: refine it,"
    echo "do not rebuild, and never delete a business rule to silence a finding."
    echo; echo "FINDINGS (fix every one):"; printf '%s\n' "$findings"
    echo; echo "DONE WHEN:"
    echo "- Every finding above is addressed and the gates still pass."
  } > "$fix"
  cp "$fix" "loop/tasks/$(basename "$fix")"           # survives across runs
  log "review($chair): FAIL -> $(basename "$fix") queued P0, NOTHING reverted (fix-forward)"
}

# ---------- cycle loop ----------
CYC=0; GREENS=0; LASTGREEN=0; STERILE_SAID=0
while :; do
  NOW="$(date +%s)"
  REMAIN=$(( DEADLINE - NOW ))
  [ "$REMAIN" -lt "$LOOP_MIN_REMAINING" ] && { log "deadline near, stopping"; break; }
  [ -f loop/STOP ] && { log "STOP file honored"; break; }
  reap
  CARD="$(pick_card)"
  [ -z "$CARD" ] && { log "queue complete"; break; }
  NAME="$(basename "$CARD" .md)"
  CYC=$(( CYC + 1 ))
  if [ $(( CYC - LASTGREEN )) -ge 5 ] && [ "$STERILE_SAID" = 0 ]; then
    log "STERILE: $(( CYC - LASTGREEN )) cycles without a green, read the cycle logs NOW"
    STERILE_SAID=1
  fi

  # AUTODONE: only for non-repair cards, no OR-probes, all probes pass.
  # Repair-card refusal: an observed defect does not fix itself, green probes
  # there mean non-discriminant probes.
  if is_repair_card "$NAME"; then
    if run_probes "$CARD" "$WT" "$LOOP_PROBE_TIMEOUT"; then
      log "REFUSED autodone (repair card $NAME): probes already pass, so the probes are bad, going through maker + gates"
    fi
  elif ! card_has_or_probes "$CARD" && run_probes "$CARD" "$WT" "$LOOP_PROBE_TIMEOUT"; then
    log "AUTODONE: $NAME (all probes already pass)"
    mv "$CARD" "loop/state/done/$NAME.md"; echo "- $NAME: AUTODONE" >> "$REPORT"
    continue
  fi

  # model routing: escalated cards use the stronger model when configured
  MODEL="$LOOP_MODEL"
  case "$NAME" in zz-E-*) [ -n "$LOOP_ESCALATION_MODEL" ] && MODEL="$LOOP_ESCALATION_MODEL" ;; esac
  log "CYCLE $CYC: $NAME (agent=$LOOP_AGENT${MODEL:+/$MODEL})"

  # prompt
  PF="$(mktemp)"; CLOG="loop/logs/cycle-$RUN-$CYC-$NAME.log"
  { echo "You are the MAKER of an autonomous engineering loop. Execute this card"
    echo "completely: edit or create whatever files it takes inside this project"
    echo "folder, then BUILD and TEST in your terminal, read the errors, fix, and"
    echo "iterate until everything compiles and the tests pass. Do not stop while"
    echo "a compile error you can see remains. Never weaken a test or delete a"
    echo "business rule to make something pass. When it builds green, stop."
    echo; [ -n "$STACK_BRIEF" ] && { echo "## STACK"; echo "$STACK_BRIEF"; echo; }
    echo "## GATES THAT WILL JUDGE YOU"
    for g in ${GATE_CMDS[@]+"${GATE_CMDS[@]}"}; do echo "- $g"; done
    echo; echo "## THE CARD"; cat "$CARD"
  } > "$PF"

  ( cd "$WT" && maker_run "$PF" "$MODEL" ) > "$CLOG" 2>&1
  MRC=$?
  rm -f "$PF"

  # infra classes: pause, preserve the card, never blame or escalate it
  CLASS="$(classify_infra "$CLOG")"
  if [ -n "$CLASS" ]; then
    case "$CLASS" in
      overloaded)
        OVERLOAD_N=$(( OVERLOAD_N + 1 ))
        if [ "$OVERLOAD_N" -le 3 ]; then
          log "PAUSE overloaded (episode $OVERLOAD_N/3): provider saturated, card preserved, 3 min"
          git -C "$WT" reset --hard >/dev/null 2>&1; git -C "$WT" clean -fd -e loop >/dev/null 2>&1
          sleep 180; continue
        fi ;;
      network)
        log "PAUSE network: endpoint unreachable, waiting in 5 min slices, card preserved"
        git -C "$WT" reset --hard >/dev/null 2>&1; git -C "$WT" clean -fd -e loop >/dev/null 2>&1
        while [ $(( DEADLINE - $(date +%s) )) -gt "$LOOP_MIN_REMAINING" ]; do
          sleep 300
          curl -sI --max-time 8 https://api.anthropic.com >/dev/null 2>&1 && { log "network back"; break; }
        done
        continue ;;
      quota)
        log "PAUSE quota/rate-limit: 20 min, card preserved (reactive pause, provider's own signal)"
        git -C "$WT" reset --hard >/dev/null 2>&1; git -C "$WT" clean -fd -e loop >/dev/null 2>&1
        sleep 1200; continue ;;
    esac
  fi

  # verdict: gates, then probes. The card's DONE definition is the probes.
  EXTRA_GATE=""
  case "$NAME" in 00-E2E*) EXTRA_GATE="$E2E_CMD" ;; esac
  VERDICT=green
  if [ "$MRC" -ne 0 ] && ! git -C "$WT" status --porcelain | grep -q .; then
    log "RED maker (rc=$MRC, no changes)"; VERDICT=red
  elif ! run_gates "$EXTRA_GATE"; then
    VERDICT=red
  elif ! run_probes "$CARD" "$WT" "$LOOP_PROBE_TIMEOUT"; then
    log "RED probes: work gated green but the card's DONE definition is not met"
    VERDICT=red
  elif ! git -C "$WT" status --porcelain | grep -q .; then
    # legit no-change was already handled by AUTODONE above. Here the maker
    # produced no diff on a card that was not eligible: nothing was built.
    # Repair cards included: an observed defect requires a diff by definition.
    log "RED no-change: maker produced no diff (card was not eligible for AUTODONE)"; VERDICT=red
  fi

  if [ "$VERDICT" = green ]; then
    # lock discipline: a manifest change without its lock kills the NEXT run's install
    if [ -n "$STACK_LOCK_MANIFEST" ] && git -C "$WT" status --porcelain | grep -q "$(basename "$STACK_LOCK_MANIFEST")" \
       && [ -n "$STACK_LOCK_SYNC_CMD" ]; then
      ( cd "$WT" && bash -c "$STACK_LOCK_SYNC_CMD" ) >/dev/null 2>&1 && log "lock file re-synced (manifest changed)"
    fi
    git -C "$WT" add -A >/dev/null 2>&1
    git -C "$WT" commit -q -m "feat: $NAME [loop]" || { log "RED commit failed"; VERDICT=red; }
  fi

  if [ "$VERDICT" = green ]; then
    SHA="$(git -C "$WT" rev-parse --short HEAD)"
    DUR_MIN=$(( ( $(date +%s) - NOW ) / 60 ))
    log "GREEN $SHA (${DUR_MIN}m): $NAME"
    echo "- $NAME: GREEN $SHA (${DUR_MIN}m)" >> "$REPORT"
    mv "$CARD" "loop/state/done/$NAME.md"
    GREENS=$(( GREENS + 1 )); LASTGREEN=$CYC; STERILE_SAID=0
    review_green "$NAME" "$SHA"
  else
    # bank the attempt (diff + log tail), then reset to zero: atomicity
    git -C "$WT" diff > "loop/wip/$NAME-$RUN.patch" 2>/dev/null
    tail -30 "$CLOG" > "loop/wip/$NAME-$RUN.findings" 2>/dev/null
    git -C "$WT" reset --hard >/dev/null 2>&1
    git -C "$WT" clean -fd -e loop >/dev/null 2>&1
    AF="loop/state/attempts/$NAME"; ATT=$(( $(cat "$AF" 2>/dev/null || echo 0) + 1 )); echo "$ATT" > "$AF"
    if [ "$ATT" -ge "$LOOP_MAX_ATTEMPTS" ]; then
      log "RED final ($ATT attempts): $NAME parked in failed/ (patch banked in loop/wip/)"
      echo "- $NAME: FAILED after $ATT attempts (patch banked)" >> "$REPORT"
      mv "$CARD" "loop/state/failed/$NAME.md"
    elif ! is_repair_card "$NAME" && [ -n "$LOOP_ESCALATION_MODEL$LOOP_MAKER_TEMPLATE" ]; then
      log "RED attempt $ATT: $NAME re-queued as zz-E-$NAME (escalation model, banked findings attached)"
      { cat "$CARD"; echo; echo "## PREVIOUS ATTEMPT (banked)";
        echo '~~~'; tail -20 "loop/wip/$NAME-$RUN.findings" 2>/dev/null; echo '~~~'; } \
        > "loop/state/queue/zz-E-$NAME.md"
      rm -f "$CARD"
    else
      log "RED attempt $ATT: $NAME stays in queue for one retry"
    fi
  fi
done

# ---------- close ----------
# e2e phase: assembly truth. Per-card gates cannot see integration breakage
# (proven: 10 green cards, full suite 47 passed / 13 failed).
if [ -n "$E2E_CMD" ] && [ "${LOOP_DRY_RUN:-0}" != 1 ]; then
  if [ -n "$E2E_BUILD_ARTIFACT" ] && [ -n "$E2E_BUILD_SRC" ] && [ -n "$E2E_PREBUILD_CMD" ]; then
    if [ ! -e "$WT/$E2E_BUILD_ARTIFACT" ] || [ -n "$(find "$WT/$E2E_BUILD_SRC" -newer "$WT/$E2E_BUILD_ARTIFACT" -print -quit 2>/dev/null)" ]; then
      log "e2e: served build stale, rebuilding first (stale dist = phantom failures)"
      ( cd "$WT" && bash -c "$E2E_PREBUILD_CMD" ) >/dev/null 2>&1
    fi
  fi
  log "e2e phase: $E2E_CMD"
  ( cd "$WT" && timeout 1200 bash -c "$E2E_CMD" ) > "loop/logs/e2e-$RUN.log" 2>&1
  E2ERC=$?
  if [ "$E2ERC" -eq 0 ]; then
    log "e2e GREEN"; echo "- e2e: GREEN" >> "$REPORT"
  else
    log "e2e RED (rc=$E2ERC): repair card queued for the next run (see loop/logs/e2e-$RUN.log)"
    { echo "# Repair the end-to-end suite"; echo; echo "SCOPE: full"; echo "VALUE: P0"
      echo; echo "USE CASE:"
      echo "The full suite failed at run close while every per-card gate was green:"
      echo "assembly breakage. Run it yourself (bash loop/verify.sh --e2e), read the"
      echo "failures, decide per spec whether the SPEC is stale or the CODE broke the"
      echo "experience, and fix accordingly. Never weaken a spec whose expectation is"
      echo "the correct behavior. Iterate until 0 failed."
      echo; echo "## LAST FAILURE TAIL"; echo '~~~'
      tail -30 "loop/logs/e2e-$RUN.log" | iconv -f UTF-8 -t UTF-8 -c; echo '~~~'
      echo; echo "DONE WHEN:"
      echo "- docs/e2e-status.md exists, first line exactly: RESULTAT: 0 failed"
      echo "- it quotes the verbatim summary line of your last full run, with date"
      echo; echo "PROBE: test -f docs/e2e-status.md"
      echo "PROBE: grep -q \"RESULTAT: 0 failed\" docs/e2e-status.md"
    } > "loop/tasks/00-E2E-repair-suite.md"
    echo "- e2e: RED, repair card seeded" >> "$REPORT"
  fi
fi
reap
log "CLOSE: $GREENS green over $CYC cycles. Report: $REPORT"
log "Greens live on branch $BR. Verify independently (gates + full e2e, quiet machine), then the OWNER merges: git merge --no-ff $BR"
