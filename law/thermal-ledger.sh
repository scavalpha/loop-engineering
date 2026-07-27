#!/usr/bin/env bash
# ENREGISTREUR CPU+THERMIQUE persistant. Repond a la question ouverte des 6 reboots
# machine sans trace (theorie playwright falsifiee le 15/07: 4e reboot a 35 min du
# dernier playwright, mvn compilait a l'instant). Hypothese restante: charge/thermique.
# Ecrit une ligne toutes les 30s dans un fichier HORS worktree (survit au reboot et au
# nettoyage du worktree): horodatage, load 1/5/15, pression thermique, memoire libre,
# et les 3 process les plus gourmands en CPU. Au prochain reset, les dernieres lignes
# datent de <30s avant: on voit si le CPU/thermique etait au plafond.
# Lance par launchd (RunAtLoad) => tourne des le boot, cout negligeable (un ps/30s).
set -u
LEDGER="${THERMAL_LEDGER:-$HOME/.loop-engineering/thermal-ledger.log}"
mkdir -p "$(dirname "$LEDGER")"
echo "=== ledger demarre $(date '+%F %T') (pid $$) ===" >> "$LEDGER"
pressure_label(){ case "$1" in 1) echo normal;; 2) echo WARN;; 4) echo CRITICAL;; *) echo "?$1";; esac; }
while :; do
  TS="$(date '+%F %T')"
  LOAD="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}')"
  # pression memoire kernel: 1=normal 2=warn 4=critique (le vrai signal, pas le "free")
  MP="$(pressure_label "$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null)")"
  SWAP="$(sysctl -n vm.swapusage 2>/dev/null | grep -oE 'used = [0-9.]+[MG]' | head -1 | awk '{print $3}')"
  THERM="$(pmset -g therm 2>/dev/null | grep -oE 'CPU_Speed_Limit *= *[0-9]+' | grep -oE '[0-9]+$')"
  [ -z "$THERM" ] && THERM="100"   # 100 = pas de bridage thermique; <100 = throttle en cours
  TOP3="$(ps -Ao pcpu,comm -r 2>/dev/null | sed -n '2,4p' | awk '{printf "%s(%s%%) ", $2, $1}')"
  printf '%s | load%s | mempress=%s swap=%s cpuspeed=%s%% | %s\n' "$TS" "$LOAD" "$MP" "${SWAP:-?}" "$THERM" "$TOP3" >> "$LEDGER"
  # rotation douce: garder les 5000 dernieres lignes
  LC="$(wc -l < "$LEDGER" 2>/dev/null || echo 0)"
  [ "${LC:-0}" -gt 6000 ] && tail -5000 "$LEDGER" > "$LEDGER.tmp" && mv "$LEDGER.tmp" "$LEDGER"
  sleep 60
done
