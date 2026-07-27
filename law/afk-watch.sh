#!/usr/bin/env bash
# AFK watcher: turns every idle minute into loop time. Usage: loop/afk-watch.sh
# Run it in a terminal and forget it (Ctrl-C to stop the watcher itself).
#
# - You idle >= IDLE_START (10 min) and preflight is sane -> launches the loop
#   (LOOP_RESUME=1, so all AFK sessions accumulate on ONE loop/overnight branch).
# - You come back (idle resets) -> touches STOP (graceful, between cycles); if a
#   cycle is still grinding after GRACE seconds, kills the maker/checker processes.
#   Safe by architecture: the worktree re-forks/resumes cleanly next time, your
#   main checkout is never touched.
# - Never launches while the loop already runs, while 8081 is busy (your review
#   servers), on battery, or if loop/STOP exists in the main repo (master kill).
set -uo pipefail
MAIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WT="${LOOP_WORKTREE_DIR:-$(cd "$MAIN/.." && pwd)/$(basename "$MAIN")-loop}"
IDLE_START=600      # seconds of idle before launching
GRACE=90            # seconds after return before hard-killing a mid-cycle maker
SESSION_DL="+8h"    # rolling deadline per AFK session (deadline guard stops it anyway)
LOG="$MAIN/loop/logs/afk-watch.log"
mkdir -p "$MAIN/loop/logs"

idle_s(){ ioreg -c IOHIDSystem 2>/dev/null | awk '/HIDIdleTime/ {print int($NF/1000000000); exit}'; }
# v5.7.2: prefer the pidfile (survives the snapshot-exec rename), fall back to pgrep
# on both the launcher name AND the /tmp/loop-driver-<pid> snapshot name.
loop_running(){
  local pf="$MAIN/loop/RUNNING"
  [ -f "$pf" ] && kill -0 "$(cat "$pf" 2>/dev/null)" 2>/dev/null && return 0
  pgrep -f 'loop-overnight\.sh|loop-driver-[0-9]' >/dev/null 2>&1
}
say(){ printf '[afk %s] %s\n' "$(date +%H:%M:%S)" "$1" | tee -a "$LOG"; }

say "watcher started (launch after ${IDLE_START}s idle, graceful stop on return)"
RETURNED_AT=0
while :; do
  I="$(idle_s)"; I="${I:-0}"
  if loop_running; then
    if [ "$I" -lt 60 ]; then
      # user is back: graceful stop, then hard-kill the cycle if it overstays
      if [ ! -f "$WT/loop/STOP" ]; then
        touch "$WT/loop/STOP" 2>/dev/null
        RETURNED_AT=$(date +%s)
        say "user back, STOP set (graceful)"
        osascript -e 'display notification "Retour détecté, arrêt en fin de cycle" with title "Loop AFK"' 2>/dev/null || true
      elif [ "$RETURNED_AT" -gt 0 ] && [ $(( $(date +%s) - RETURNED_AT )) -gt "$GRACE" ]; then
        say "grace expired, killing OUR maker/checker only (cwd under $WT)"
        # scope kills to processes running inside the loop worktree, never machine-wide
        # (review #2): filter hermes/codex PIDs by their working directory.
        for pid in $(pgrep -f 'hermes -m' 2>/dev/null) $(pgrep -f 'codex exec' 2>/dev/null); do
          cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
          case "$cwd" in "$WT"*) kill -9 "$pid" 2>/dev/null;; esac
        done
        RETURNED_AT=0
      fi
    fi
  else
    RETURNED_AT=0
    if [ "$I" -ge "$IDLE_START" ]; then
      if [ -f "$MAIN/loop/STOP" ]; then
        say "master STOP present in main repo, not launching"
      elif lsof -ti tcp:8081 >/dev/null 2>&1; then
        say "8081 busy (review servers?), not launching"
      elif ! pmset -g ps | grep -q "AC Power"; then
        say "on battery, not launching"
      else
        say "idle $(( I / 60 ))min, launching loop ($SESSION_DL, resume mode)"
        rm -f "$WT/loop/STOP" 2>/dev/null
        ( cd "$MAIN" && LOOP_RESUME=1 nohup ./loop/loop-overnight.sh "$SESSION_DL" >> "$MAIN/loop/logs/afk-sessions.log" 2>&1 & )
        sleep 20
      fi
    fi
  fi
  sleep 30
done
