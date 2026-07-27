#!/usr/bin/env bash
# v6.21 DIGEST MATIN. Un seul message Telegram consolide en fin de run (ou rejouable a
# la main / via launchd), au lieu des pings epars. Compose depuis les artefacts committes:
# dernier rapport, metrics, quota, debit maker, couverture, candidat fini, file en attente.
# Autonome: aucune dependance a un hermes vivant, juste le token du .env comme notify_phone.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"; cd "$ROOT"
R="$(ls -t loop/reports/report-*.md 2>/dev/null | head -1)"
[ -f "$R" ] || { echo "[digest] aucun rapport"; exit 0; }

line(){ grep -m1 "$1" "$R" 2>/dev/null | sed "s/^- *//"; }
SUM="$(grep -m1 '^- green:' "$R" | sed 's/^- *//')"
E2E="$(line 'E2E RUNTIME:')"
COV="$(line 'COUVERTURE:')"
CAND="$([ -f loop/DONE-CANDIDATE ] && echo 'CANDIDAT FINI declare' || true)"
MET="$(tail -1 loop/reports/metrics.tsv 2>/dev/null)"
LAWP="$(printf '%s' "$MET" | awk -F'\t' '{print $8}')"
PERF="$(grep -A3 'DEBIT MAKER' "$R" 2>/dev/null | grep 's/vert' | sed 's/^ *- */  /' | tr '\n' ' ')"
QN="$(ls loop/state/queue/*.md 2>/dev/null | wc -l | tr -d ' ')"
NEXT="$(ls loop/state/queue/*.md 2>/dev/null | sort | head -1 | xargs -I{} basename {} .md 2>/dev/null)"
QUOTA="$(tail -2 loop/reports/usage.tsv 2>/dev/null | tr '\n' ' ')"
FB="$(line 'FEEDBACK:')"
COUNCIL="$(grep -c 'CONSEIL' "$R" 2>/dev/null)"

MSG="🌅 Digest run $(basename "$R" .md | sed 's/report-//')
${SUM:-pas de resume}
${E2E:+• $E2E
}${COV:+• $COV
}${CAND:+• 🏁 $CAND
}${LAWP:+• patchs de loi humains ce run: $LAWP
}${PERF:+• debit:$PERF
}${QUOTA:+• quota: $QUOTA
}${FB:+• $FB
}• file restante: $QN cartes${NEXT:+, prochaine: $NEXT}${COUNCIL:+
• conseil convoque: oui}"

# envoi Telegram (meme voie que notify_phone), sinon impression locale
if [ -f "$HOME/.hermes/.env" ]; then
  tok="$(grep -m1 '^TELEGRAM_BOT_TOKEN=' "$HOME/.hermes/.env" | cut -d= -f2-)"
  chat="$(grep -m1 '^TELEGRAM_CHAT_ID=' "$HOME/.hermes/.env" | cut -d= -f2-)"
  if [ -n "$tok" ] && [ -n "$chat" ]; then
    curl -s --max-time 15 "https://api.telegram.org/bot$tok/sendMessage" \
      -d "chat_id=$chat" --data-urlencode "text=[${LOOP_PROJECT_TAG:-$(basename "$MAIN" 2>/dev/null || basename "$PWD")}] $MSG" >/dev/null 2>&1 && { echo "[digest] envoye"; exit 0; }
  fi
fi
printf '%s\n' "$MSG"
