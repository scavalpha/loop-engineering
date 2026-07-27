#!/usr/bin/env bash
# Gate v4: front build + service tests + runtime smoke QA, scope-aware.
# VERIFY_SCOPE=front skips backend phases; =back skips the front build; default full.
# Every phase time-bounded; port kill scoped to our own app.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export NG_CLI_ANALYTICS=false CI=true
SCOPE="${VERIFY_SCOPE:-full}"
# contrat stack (portabilite v1)
# v6.84 (relecture du stack.sh d'un projet portage): les defauts ci-dessous portaient le NOM du projet
# d'origine en dur sans forme ${:-} ni marqueur. Ca marchait par
# accident (le sourcing du contrat vient apres et ecrase), mais un nom de projet dans
# la LOI viole la regle anti-fuite: defauts generiques, le contrat porte les noms.
BACK_DIR="${BACK_DIR:-backend}"; FRONT_DIR="${FRONT_DIR:-frontend}"   # stack-default
BACK_PORT="${BACK_PORT:-8081}"; BACK_PROC_PATTERN="${BACK_PROC_PATTERN:-spring-boot|\bjava\b}"       # stack-default
SMOKE_PATH="${SMOKE_PATH:-/api/health}"; HEALTH_PATH="${HEALTH_PATH:-/actuator/health}"
[ -f "$ROOT/loop/stack.sh" ] && . "$ROOT/loop/stack.sh"
# v5.7.3: warm Maven daemon (mvnd) kills the per-call JVM startup tax; fallback ./mvnw
_MVND="$HOME/.sdkman/candidates/mvnd/current/bin/mvnd"                     # stack-default
MVN="${LOOP_MVN:-$([ -x "$_MVND" ] && echo "$_MVND" || echo ./mvnw)}"      # stack-default
# v6.43 contrat v2: le gate complet aussi est contractuel (defauts = historique exact)
GATE_FRONT_CMD="${GATE_FRONT_CMD:-npx ng build}"                           # stack-default
VERIFY_BACK_CMD="${VERIFY_BACK_CMD:-$MVN -q test}"                         # stack-default
BOOT_BACK_CMD="${BOOT_BACK_CMD:-$MVN spring-boot:run}"                     # stack-default
HEALTH_OK_PATTERN="${HEALTH_OK_PATTERN:-\"UP\"}"
PSLUG="$(basename "$ROOT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
FLOG=/tmp/$PSLUG-verify-front.log
SLOG=/tmp/$PSLUG-verify-svc.log
BLOG=/tmp/$PSLUG-verify-boot.log

# kill $BACK_PORT listeners ONLY if they look like our service (java/spring/our app)
kill_our_port(){
  for p in $(lsof -ti tcp:$BACK_PORT 2>/dev/null); do
    if ps -p "$p" -o command= 2>/dev/null | grep -qiE "$BACK_PROC_PATTERN"; then
      kill -9 "$p" 2>/dev/null
    fi
  done
  true
}

# v6.62: gate du SIDECAR (2e repo optionnel du perimetre). Ne tourne QUE si le maker l'a modifie
# (arbre sale) OU si la carte est scope=sidecar: sinon zero cout. Garde dure: repo git
# valide et distinct du repo principal. Un test rouge du sidecar = RED, comme le back.
if [ -n "${SIDECAR_DIR:-}" ] && [ -d "$SIDECAR_DIR/.git" ]; then
  SC_DIRTY="$(git -C "$SIDECAR_DIR" status --porcelain 2>/dev/null | head -1)"
  if [ -n "$SC_DIRTY" ] || [ "$SCOPE" = "sidecar" ]; then
    echo "[verify] sidecar tests ($SIDECAR_DIR)..."
    if ! timeout 900 bash -c "cd '$SIDECAR_DIR' && $SIDECAR_GATE_CMD" >"/tmp/$PSLUG-sidecar.log" 2>&1; then
      echo "[verify] SIDECAR TESTS FAILED (or timed out)"; tail -35 "/tmp/$PSLUG-sidecar.log"; exit 1
    fi
    echo "[verify] sidecar GREEN"
  fi
fi

if [ "$SCOPE" != "back" ] && [ -n "$FRONT_DIR" ]; then
  LITE_OK="$ROOT/loop/state/lite.ok"
  # content hash (listing + tracked diff + untracked-file contents) — must match
  # run-cycle's tree_hash so a stale marker can never skip a build on a changed tree.
  TREE_NOW="$( { git -C "$ROOT" status --porcelain 2>/dev/null
    git -C "$ROOT" diff HEAD 2>/dev/null
    git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f; do printf '>>%s\n' "$f"; cat "$ROOT/$f" 2>/dev/null; done
  } | shasum -a 256 | cut -d' ' -f1)"
  if [ -f "$LITE_OK" ] && [ "$(cat "$LITE_OK")" = "$TREE_NOW" ]; then
    echo "[verify] front build skipped (identical tree already built clean by lite check)"
    rm -f "$LITE_OK"
  else
    rm -f "$LITE_OK"
    echo "[verify] front build..."
    if [ -d "$ROOT/$FRONT_DIR" ] && ! timeout 420 bash -c "cd '$ROOT/$FRONT_DIR' && $GATE_FRONT_CMD" >"$FLOG" 2>&1; then
      echo "[verify] FRONT BUILD FAILED (or timed out)"; tail -25 "$FLOG"; exit 1
    fi
  fi
else
  echo "[verify] front build skipped (scope=back)"
fi

if [ "$SCOPE" = "front" ] || [ -z "$BACK_DIR" ]; then
  echo "[verify] backend phases skipped (scope=$SCOPE, BACK_DIR='${BACK_DIR}')"
  echo "[verify] GREEN (front build only)"
  exit 0
fi

echo "[verify] service tests..."
if ! timeout 900 bash -c "cd '$ROOT/$BACK_DIR' && $VERIFY_BACK_CMD" >"$SLOG" 2>&1; then
  echo "[verify] SERVICE TESTS FAILED (or timed out)"; tail -35 "$SLOG"; exit 1
fi

# ---------- runtime smoke QA ----------
echo "[verify] runtime smoke..."
kill_our_port; sleep 1

# no -q on the smoke: when boot fails, the SPRING stacktrace (bean wiring, seeder crash)
# must land in $BLOG; -q reduced it to an opaque 8-line MojoExecutionException (2026-07-05).
( cd "$ROOT/$BACK_DIR" && timeout 300 $BOOT_BACK_CMD ) >"$BLOG" 2>&1 &
BOOT_PID=$!
# v6.46 (fuite decouverte par release-smoke): tuer l'ARBRE du boot, pas le subshell seul.
# L'enfant (python http.server, spring...) survivait au kill du parent, gardait le port,
# et TOUTES les cartes suivantes echouaient au boot (Errno 48). pkill -P = PID-scope.
smoke_cleanup(){ pkill -P "$BOOT_PID" 2>/dev/null; kill -9 "$BOOT_PID" 2>/dev/null; kill_our_port; true; }
trap smoke_cleanup EXIT

up=""
for i in $(seq 1 60); do
  if curl -fsS --max-time 2 http://localhost:$BACK_PORT$HEALTH_PATH 2>/dev/null | grep -q "$HEALTH_OK_PATTERN"; then up=1; break; fi
  sleep 2
done
if [ -z "$up" ]; then
  echo "[verify] SMOKE FAILED: app did not become healthy in 120s"; tail -30 "$BLOG"; exit 1
fi

CODE="$(curl -s -o /tmp/$PSLUG-smoke.json -w '%{http_code}' --max-time 5 http://localhost:$BACK_PORT$SMOKE_PATH)"
# v6.61 SMOKE AUTH-AWARE (3 RED consecutifs sur 42-auth-jwt-back, 14/07: la carte exige
# 401 sans jeton sur /api/**, le smoke attendait 200 nu -> la carte ne pouvait JAMAIS
# verdir, conflit loi-contre-feature). Si l'app repond 401/403 et que le contrat stack
# fournit SMOKE_TOKEN_CMD (commande qui imprime un jeton dev), la loi s'authentifie et
# retente avec Bearer. Sans SMOKE_TOKEN_CMD, comportement historique inchange.
if { [ "$CODE" = "401" ] || [ "$CODE" = "403" ]; } && [ -n "${SMOKE_TOKEN_CMD:-}" ]; then
  TOK="$(timeout 20 bash -c "$SMOKE_TOKEN_CMD" 2>/dev/null | tail -1)"
  if [ -n "$TOK" ]; then
    CODE="$(curl -s -o /tmp/$PSLUG-smoke.json -w '%{http_code}' --max-time 5 -H "Authorization: Bearer $TOK" http://localhost:$BACK_PORT$SMOKE_PATH)"
    echo "[verify] smoke: app protegee, jeton dev obtenu, retente avec Bearer -> HTTP $CODE"
  else
    echo "[verify] SMOKE FAILED: $SMOKE_PATH protege (HTTP $CODE) mais SMOKE_TOKEN_CMD n'a rendu aucun jeton"; exit 1
  fi
fi
if [ "$CODE" != "200" ]; then
  echo "[verify] SMOKE FAILED: GET $SMOKE_PATH -> HTTP $CODE"; exit 1
fi
# v6.46: l'assertion de contenu est CONTRACTUELLE (SMOKE_OK_CMD, recoit SMOKE_FILE).
# L'ancienne loi exigeait en dur "un tableau JSON non vide": une attente PRODUIT precise
# cablee dans la loi (RED garanti sur tout stack dont le smoke ne rend pas un tableau).
SMOKE_OK_CMD="${SMOKE_OK_CMD:-python3 -c \"import json,os;d=json.load(open(os.environ['SMOKE_FILE']));assert isinstance(d,list) and len(d)>=1\"}"   # stack-default
if ! SMOKE_FILE="/tmp/$PSLUG-smoke.json" timeout 30 bash -c "$SMOKE_OK_CMD" 2>/dev/null; then
  echo "[verify] SMOKE FAILED: contenu de $SMOKE_PATH rejete par SMOKE_OK_CMD"; exit 1
fi

smoke_cleanup
trap - EXIT
echo "[verify] GREEN (build + tests + smoke)"
exit 0
