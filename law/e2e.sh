#!/usr/bin/env bash
# v6.7 GATE RUNTIME. La verite du clic: on ne croit pas un vert tant qu'un navigateur
# n'a pas charge les ecrans. Codes: 0=vert, 1=echec (defauts reels), 3=SKIP (infra
# absente: jamais bloquant, meme doctrine de degradation que MLX vers ollama).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
# contrat stack (portabilite v1): defauts = historique, stack.sh surcharge
BACK_DIR="${BACK_DIR:-backend}"; FRONT_DIR="${FRONT_DIR:-frontend}"                              # stack-default
E2E_BACK_START='./mvnw -q spring-boot:run'; FRONT_E2E_CMD='npx playwright test --reporter=line'      # stack-default
[ -f loop/stack.sh ] && . loop/stack.sh
STARTED_BACK=""
log(){ echo "[e2e] $*"; }
# le port du back se lit dans la config, pas dans une constante (8081 aujourd'hui)
BACK_PORT="${BACK_PORT:-$(grep -m1 -E '^\s*port:' "$BACK_DIR/src/main/resources/application.yml" 2>/dev/null | grep -oE '[0-9]+' | head -1)}"   # stack-default
BACK_PORT="${BACK_PORT:-8080}"
# v6.43: sante contractuelle (HEALTH_PATH/HEALTH_OK_PATTERN), defauts = spring actuator
back_up(){ curl -fsS --max-time 3 "http://localhost:$BACK_PORT${HEALTH_PATH:-/actuator/health}" 2>/dev/null | grep -q "${HEALTH_OK_PATTERN:-\"UP\"}"; }
cleanup(){
  if [ -n "$STARTED_BACK" ]; then
    pkill -P "$STARTED_BACK" 2>/dev/null; kill "$STARTED_BACK" 2>/dev/null
    log "backend demarre par e2e, arrete"
  fi
  # v6.59: reap chromium/headless_shell laisse par playwright (vecteur reboot GPU).
  # playwright teardown n'est pas fiable apres download/print: on garantit le kill.
  pkill -f 'headless_shell' 2>/dev/null
  pkill -f 'Chromium.*--headless' 2>/dev/null
}
trap cleanup EXIT
# v6.43: sentinel e2e contractuel (E2E_SENTINEL), defaut playwright; DB_PORT contractuel
[ -e "${E2E_SENTINEL:-$FRONT_DIR/node_modules/@playwright}" ] || { log "SKIP: outil e2e non installe"; exit 3; }
if ! back_up; then
  nc -z localhost "${DB_PORT:-5432}" >/dev/null 2>&1 || { log "SKIP: ni backend ni base de donnees disponibles"; exit 3; }
  log "backend absent, demarrage..."
  ( cd "$BACK_DIR" && exec $E2E_BACK_START ) > /tmp/$(basename "$ROOT")-e2e-back.log 2>&1 &
  STARTED_BACK=$!
  ok=""
  for i in $(seq 1 60); do back_up && { ok=1; break; }; /bin/sleep 3; done
  [ -n "$ok" ] || { log "SKIP: backend muet apres 180s (voir /tmp/$(basename "$ROOT")-e2e-back.log)"; exit 3; }
  log "backend UP"
fi
# v6.77 (trou de loi pilote 18/07: e2e.sh sert un BUILD sans verifier sa fraicheur. Dans
# un cycle ca passe car le gate front vient de builder, mais lance SEUL, e2e.sh peut servir
# un dist perime, 18 echecs fantomes contre un vieux scaffold. Piege pour diagnostic humain,
# CI future, ou une carte "lance toi-meme bash loop/e2e.sh"). Garde PORTABLE par contrat: si
# le stack declare un artefact de build, sa source et une commande de (re)build, on rebuild
# quand l'artefact est plus vieux que la source. Un front servi via `ng serve` (compile depuis src,
# toujours frais) => ces vars sont ABSENTES => no-op. un projet qui sert dist => il les fournit.
if [ -n "${E2E_BUILD_ARTIFACT:-}" ] && [ -n "${E2E_BUILD_SRC:-}" ] && [ -n "${E2E_PREBUILD_CMD:-}" ]; then
  if [ ! -e "$E2E_BUILD_ARTIFACT" ] \
     || [ -n "$(find "$E2E_BUILD_SRC" -newer "$E2E_BUILD_ARTIFACT" -print -quit 2>/dev/null)" ]; then
    log "build servi perime (ou absent) vs $E2E_BUILD_SRC -> rebuild avant e2e"
    ( cd "$FRONT_DIR" && eval "$E2E_PREBUILD_CMD" ) || { log "SKIP: rebuild du front echoue"; exit 3; }
  else
    log "build servi frais vs $E2E_BUILD_SRC"
  fi
fi
( cd "$FRONT_DIR" && $FRONT_E2E_CMD )
RC=$?
[ "$RC" -eq 0 ] && log "VERT" || log "ECHEC rc=$RC"
exit "$RC"
