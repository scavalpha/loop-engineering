#!/usr/bin/env bash
# v6.57 RESURRECTEUR AU BOOT. Deux reboots machine sans trace en 2 jours (11-12/07),
# chacun pendant un run actif; celui de 09:00 a coute 4h de fenetre. Ce script est lance
# par un LaunchAgent (RunAtLoad) a CHAQUE demarrage de session:
#   - NIGHT-PLAN (deadline epoch) present ET dans le futur ET pas de STOP ET pas de
#     driver vivant => relance le driver pour le RELIQUAT avec l'env NIGHT-ENV.
#   - sinon: sort sans rien faire (0 cout, 0 effet de bord).
# Il ne demarre JAMAIS un run neuf: il ne fait que terminer une fenetre deja ORDONNEE
# par le proprietaire (NIGHT-PLAN n'existe que si un run a ete lance explicitement;
# STOP/deadline atteinte l'effacent). Doctrine no-launch-without-order respectee.
set -u
MAIN="${LOOP_MAIN_DIR:-$HOME/dev/myproject}"
LOG="/tmp/loop-boot-resurrect.log"
exec >>"$LOG" 2>&1
echo "=== boot-resurrect $(date '+%F %H:%M:%S') ==="
PLAN="$MAIN/loop/NIGHT-PLAN"
[ -f "$PLAN" ] || { echo "pas de NIGHT-PLAN, rien a faire"; exit 0; }
[ -f "$MAIN/loop/STOP" ] && { echo "STOP present, pas de resurrection"; exit 0; }
DL="$(cat "$PLAN" 2>/dev/null | tr -cd '0-9')"
NOW="$(date +%s)"
[ -n "$DL" ] && [ "$DL" -gt $(( NOW + 900 )) ] || { echo "deadline passee/trop proche ($DL vs $NOW), NIGHT-PLAN purge"; rm -f "$PLAN"; exit 0; }
# driver deja vivant? (RUNNING = pid)
RP="$(cat "$MAIN/loop/RUNNING" 2>/dev/null)"
if [ -n "$RP" ] && ps -p "$RP" >/dev/null 2>&1; then echo "driver $RP deja vivant"; exit 0; fi
# laisser le boot se poser (reseau, keychain) puis verifier le reseau
sleep 90
curl -sI --max-time 10 https://api.anthropic.com >/dev/null 2>&1 || sleep 120
REM_MIN=$(( (DL - $(date +%s)) / 60 ))
[ "$REM_MIN" -gt 15 ] || { echo "reliquat trop court (${REM_MIN}min)"; rm -f "$PLAN"; exit 0; }
# relancer avec l'env persiste, deadline = l'heure ABSOLUE d'origine
[ -f "$MAIN/loop/NIGHT-ENV" ] && . "$MAIN/loop/NIGHT-ENV"
HHMM="$(date -r "$DL" '+%H:%M')"
echo "resurrection: reliquat ${REM_MIN}min (deadline $HHMM), env NIGHT-ENV adopte"
cd "$MAIN" || exit 1
export LOOP_RESUME=1
nohup bash loop/loop-overnight.sh "$HHMM" > "/tmp/loop-resurrected-$(date +%H%M%S).log" 2>&1 &
echo "driver resuscite pid $!"
