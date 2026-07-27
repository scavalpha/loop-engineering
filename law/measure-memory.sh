#!/usr/bin/env bash
# v6.2 N6 measurement: is the profile-scoped hermes memory actually helping?
# Counts (a) memory-tool usage in cycle logs, (b) the three locked violation classes in
# checker findings (wrong-404-exception, float-for-money, NgModule usage). Compare across
# runs: classes should trend DOWN if memory (or skills) are landing.
# Usage: measure-memory.sh [logs-dir]   (default: newest archive + live logs)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
DIRS="${1:-$(ls -dt loop/archive/*/logs 2>/dev/null | head -3) loop/logs}"
echo "run-scope: $DIRS"
MEMUSE=0; V404=0; VFLOAT=0; VNGMOD=0; LOGS=0
for d in $DIRS; do
  [ -d "$d" ] || continue
  for f in "$d"/cycle-*.log; do
    [ -f "$f" ] || continue
    LOGS=$(( LOGS + 1 ))
    grep -qiE "memory_(store|recall|add)|remembered|from memory" "$f" && MEMUSE=$(( MEMUSE + 1 ))
    grep -qiE "EntityNotFoundException|ResponseStatusException.*404" "$f" && V404=$(( V404 + 1 ))
    grep -qiE "double montant|float montant|montant.*(double|float)" "$f" && VFLOAT=$(( VFLOAT + 1 ))
    grep -qiE "NgModule" "$f" && VNGMOD=$(( VNGMOD + 1 ))
  done
done
echo "cycle-logs scanned: $LOGS"
echo "memory-tool used in: $MEMUSE"
echo "violation wrong-404-exception: $V404"
echo "violation float-for-money: $VFLOAT"
echo "violation NgModule: $VNGMOD"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date +%F)" "$LOGS" "$MEMUSE" "$V404" "$VFLOAT" "$VNGMOD" >> loop/reports/memory-trend.tsv
