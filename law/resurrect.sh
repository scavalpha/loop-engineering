#!/usr/bin/env bash
# v6.3 RESURRECTEUR (launchd, toutes les 5 min). Etage 2 de la survie nocturne:
# si un run de nuit etait PLANIFIE (loop/NIGHT-PLAN contient l'epoch de fin), que le
# driver est MORT avant l'heure, sans STOP humain, et que la couche modele repond,
# on relance en RESUME (les verts de la branche sont conserves) et on notifie.
# Le driver supprime NIGHT-PLAN aux sorties LEGITIMES (deadline atteinte, STOP).
set -uo pipefail
MAIN="${LOOP_MAIN_DIR:-$HOME/dev/myproject}"
PLAN="$MAIN/loop/NIGHT-PLAN"
[ -f "$PLAN" ] || exit 0
DEADLINE_EPOCH="$(head -1 "$PLAN" | tr -cd '0-9')"
[ -n "$DEADLINE_EPOCH" ] || exit 0
NOW="$(date +%s)"
[ "$NOW" -lt "$DEADLINE_EPOCH" ] || { rm -f "$PLAN"; exit 0; }   # plan expire
[ -f "$MAIN/loop/STOP" ] && exit 0                                # volonte humaine
pgrep -f 'loop-overnight\.sh|loop-driver-[0-9]' >/dev/null 2>&1 && exit 0   # vivant
[ -f "$MAIN/loop/RUNNING" ] && exit 0
# couche modele prete? sinon on attend le prochain tick plutot que revivre-mourir
curl -fsS --max-time 5 http://localhost:11434/api/tags >/dev/null 2>&1 || exit 0
REMAIN_H=$(( (DEADLINE_EPOCH - NOW) / 3600 + 1 ))
cd "$MAIN"
[ -f "$MAIN/loop/NIGHT-ENV" ] && . "$MAIN/loop/NIGHT-ENV"
LOOP_RESUME=1 nohup bash loop/loop-overnight.sh "+${REMAIN_H}h" > "/tmp/loop-resurrected-$(date +%H%M%S).log" 2>&1 &
TOK="$(grep -m1 '^TELEGRAM_BOT_TOKEN=' "$HOME/.hermes/.env" 2>/dev/null | cut -d= -f2-)"
CHAT="$(grep -m1 '^TELEGRAM_CHAT_ID=' "$HOME/.hermes/.env" 2>/dev/null | cut -d= -f2-)"
[ -n "$TOK" ] && curl -s --max-time 10 "https://api.telegram.org/bot$TOK/sendMessage" \
  -d "chat_id=$CHAT" --data-urlencode "text=[$(basename "$MAIN")] 🔁 Resurrecteur: driver mort avant l'heure, relance RESUME +${REMAIN_H}h (pid $!)" >/dev/null 2>&1
echo "$(date '+%F %H:%M') resurrected +${REMAIN_H}h pid $!" >> "$MAIN/loop/logs/resurrect.log"
