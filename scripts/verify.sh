#!/usr/bin/env bash
# verify.sh, run the project gates exactly as the law does, by hand.
# Usage: bash loop/verify.sh          (gates only)
#        bash loop/verify.sh --e2e    (gates + full end-to-end suite)
# Run it from the checkout you want judged (main checkout or worktree).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT" || exit 1

GATE_CMDS=(); E2E_CMD=""
E2E_BUILD_ARTIFACT=""; E2E_BUILD_SRC=""; E2E_PREBUILD_CMD=""
[ -f "$SCRIPT_DIR/stack.sh" ] && . "$SCRIPT_DIR/stack.sh"

rc_total=0
for g in ${GATE_CMDS[@]+"${GATE_CMDS[@]}"}; do
  echo "[verify] gate: $g"
  if ! timeout 1800 bash -c "$g"; then echo "[verify] RED: $g"; rc_total=1; fi
done

if [ "${1:-}" = "--e2e" ] && [ -n "$E2E_CMD" ]; then
  # freshness guard: a suite serving a stale built artifact produces phantom
  # failures against last week's app
  if [ -n "$E2E_BUILD_ARTIFACT" ] && [ -n "$E2E_BUILD_SRC" ] && [ -n "$E2E_PREBUILD_CMD" ]; then
    if [ ! -e "$E2E_BUILD_ARTIFACT" ] || [ -n "$(find "$E2E_BUILD_SRC" -newer "$E2E_BUILD_ARTIFACT" -print -quit 2>/dev/null)" ]; then
      echo "[verify] served build stale, rebuilding first"
      bash -c "$E2E_PREBUILD_CMD" || { echo "[verify] RED: prebuild failed"; exit 1; }
    fi
  fi
  echo "[verify] e2e: $E2E_CMD"
  if ! timeout 1800 bash -c "$E2E_CMD"; then echo "[verify] RED: e2e"; rc_total=1; fi
fi

[ "$rc_total" -eq 0 ] && echo "[verify] ALL GREEN" || echo "[verify] RED (see above)"
exit "$rc_total"
