#!/usr/bin/env bash
# v6.30 GARDE MEMOIRE. Le 2026-07-07 un bench a alloue 17Go de MLX sur une machine 48Go
# deja aux 2/3 -> swap thrash -> freeze -> reboot force. Mac = memoire UNIFIEE (le modele
# GPU mange la RAM systeme). Avant TOUTE charge de modele, exiger la RAM libre necessaire.
# mem_available_gb: RAM reellement disponible (free + inactive + speculative + purgeable).
mem_available_gb(){
  local ps free inact spec purg
  ps=$(vm_stat | awk '/page size of/{print $8}'); ps=${ps:-16384}
  free=$(vm_stat | awk '/Pages free/{gsub(/\./,"",$3);print $3}')
  inact=$(vm_stat | awk '/Pages inactive/{gsub(/\./,"",$3);print $3}')
  spec=$(vm_stat | awk '/Pages speculative/{gsub(/\./,"",$3);print $3}')
  purg=$(vm_stat | awk '/Pages purgeable/{gsub(/\./,"",$3);print $3}')
  python3 -c "print(int(( (${free:-0}+${inact:-0}+${spec:-0}+${purg:-0}) * $ps) / 1073741824))"
}
# mem_guard <go-requis> : 0 si assez de RAM libre, 1 sinon (message sur stderr)
mem_guard(){
  local need="${1:-22}" avail
  avail="$(mem_available_gb)"
  if [ "${avail:-0}" -lt "$need" ]; then
    echo "[mem-guard] REFUS: $avail Go libres, $need Go requis. Ferme des apps (navigateurs, autres sessions) ou charge la machine moins. Un modele charge sur une machine pleine = freeze/crash (2026-07-07)." >&2
    return 1
  fi
  echo "[mem-guard] OK: $avail Go libres (>= $need requis)"
  return 0
}
# on_ac_power : 0 si sur secteur, 1 sur batterie (un pic GPU sur batterie aggrave le risque)
on_ac_power(){ pmset -g ps 2>/dev/null | grep -q "AC Power"; }
