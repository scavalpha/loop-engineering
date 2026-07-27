#!/usr/bin/env bash
# Overnight loop v5.6. Usage: loop/loop-overnight.sh <HH:MM|+Nh>
# Blocking Codex checker, escalation ladder, worktree isolation, resume, DAG-lite,
# Phase 0 (manifest), self-feed. v5.6 hardening (eng review + Codex outside voice):
# snapshot captures MAIN before exec; run artifacts archived before worktree recycle;
# STOP-interruption requeues (never fails a card); REDCOMPILE fast-RED; probe purity
# guard; escalated greens commit under original name (resume dedup); ESCALATED: tier
# marker distinct from MAKER: preference; 92-fix cards persisted durably.
set -uo pipefail
# self-snapshot: exec an immutable /tmp copy so editing this file mid-run can't corrupt
# bash's incremental read. Capture the REAL repo root BEFORE exec (no hardcoded path).
if [ -z "${LOOP_SNAPSHOT:-}" ]; then
  _SRC_MAIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  SNAP="/tmp/loop-driver-$$-$(date +%s).sh"
  cp "${BASH_SOURCE[0]}" "$SNAP" && chmod +x "$SNAP"
  LOOP_SNAPSHOT=1 LOOP_MAIN="$_SRC_MAIN" exec "$SNAP" "$@"
fi
MAIN="${LOOP_MAIN:?snapshot must pass LOOP_MAIN}"
[ -d "$MAIN/loop" ] || { echo "[loop] REFUSE: LOOP_MAIN=$MAIN has no loop/ dir"; exit 2; }

# v6.9 C1 (portabilite): contrat stack. Defauts = comportement historique exact;
# loop/stack.sh (copie de stack.d/<stack>.sh) peut tout surcharger, jamais requis.
STACK_NAME="angular-spring"; BACK_PORT="8081"
PROJECT_DOMAIN="une application web"
BACK_DIR="backend"; FRONT_DIR="frontend"
EYE_FRONT_SRC="frontend/src/app"
EYE_PAGES_DIR="frontend/src/app/pages"
EYE_CLICK_PATTERN='(click)'; EYE_STATIC_PATTERN='EXEMPLE\|Exemple\|sample'
EYE_ENTITY_PATTERN='@Entity'; EYE_ENTITY_DIR="backend/src/main/java"
EYE_SEEDER_FILE="backend/src/main/java/com/app/credit/corporate/config/DataSeeder.java"
EYE_MAQ_DIR="design/screens"; EYE_E2E_GLOB="frontend/e2e/*.spec.ts"
[ -f "$MAIN/loop/stack.sh" ] && . "$MAIN/loop/stack.sh"
# v6.45 (BUG A pilote, driver mort au semis): defauts v2 poses PAR LA LOI apres le
# source du contrat. Un stack.sh partiel (syncé sans les 13 variables v2) ne doit JAMAIS
# set-u-crasher une loi synchronisee: chaque variable de contrat que la loi touche a un
# defaut ici, la doctrine "# stack-default" vaut aussi pour les expansions.
ARCH_PROFILE="${ARCH_PROFILE:-web-fullstack}"
EYE_SRC_EXTS="${EYE_SRC_EXTS:-ts java}"      # stack-default
EYE_ENTITY_EXT="${EYE_ENTITY_EXT:-java}"     # stack-default
# v6.48.1 (decouvert au lancement du 09/07: JAVA_HOME absent d'un shell non-interactif =>
# gate_selftest lance mvnd sans JDK => preflight REFUSE sur l'arbre connu-bon, ou pire un
# resurrector relance sans JDK). L'env outillage doit etre pose AU TOP-LEVEL du driver,
# pas seulement dans les sessions maker: le gate self-test, le boot verify et le carto en
# ont besoin. La fonction contractuelle stack_maker_env pose JAVA_HOME (defaut = JDK
# sdkman); on l'appelle ici pour tout le PROCESSUS driver, une fois, apres le contrat.
if command -v stack_maker_env >/dev/null 2>&1; then stack_maker_env
else _J="$HOME/.sdkman/candidates/java/current"; [ -d "$_J" ] && export JAVA_HOME="$_J"; fi  # stack-default
case ":$PATH:" in *":${JAVA_HOME:-/nonexistent}/bin:"*) : ;; *) [ -n "${JAVA_HOME:-}" ] && export PATH="$JAVA_HOME/bin:$PATH" ;; esac
# v6.10.2: fusion descendante des lentilles du store (ce que L'AUTRE loop a appris),
# ligne a ligne, dedup, jamais d'ecrasement local
_GLENS="${LOOP_SKILLS_STORE:-$HOME/dev/loop-skills-general}/lenses-universal.md"
if [ -f "$_GLENS" ] && [ -f "$MAIN/loop/carto-lenses.md" ]; then
  grep '^- ' "$_GLENS" | while IFS= read -r _L; do
    grep -qF -- "$_L" "$MAIN/loop/carto-lenses.md" || printf '%s\n' "$_L" >> "$MAIN/loop/carto-lenses.md"
  done
  # v6.50 (pilote: le driver salissait loop/carto-lenses.md dans le checkout MAIN, ce
  # qui bloquait tout `git merge --ff-only` du consommateur, obligeant une danse de stash).
  # carto-lenses.md est de la LOI-DONNEE (lentilles apprises), pas un log: on la COMMITE si
  # elle a change, l'arbre MAIN reste propre et le worktree forke inclut l'adoption.
  if ! git -C "$MAIN" diff --quiet -- loop/carto-lenses.md 2>/dev/null; then
    git -C "$MAIN" add loop/carto-lenses.md 2>/dev/null && \
      git -C "$MAIN" commit -q -m "chore: adopt learned carto lenses from store [loop]" 2>/dev/null
  fi
fi
cd "$MAIN"
export PATH="$HOME/.local/bin:$PATH"
DL_ARG="${1:?usage: loop-overnight.sh <HH:MM|+Nh>}"
BASE="${LOOP_BASE:-dev}"
WT="${LOOP_WORKTREE:-$(cd "$MAIN/.." && pwd)/$(basename "$MAIN")-loop}"
PSLUG_D="$(basename "$WT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
# v6.13: l'escalade reste dans la famille du maker courant (panne pilote: en mode
# frontier, ESCALATED: ornith-cc devenait claude --model ornith-cc, HARD-FAIL en boucle)
case "${LOOP_MAKER_KIND:-hermes}" in
  claude) _ESC_DEFAULT="claude-opus-4-8" ;;
  codex)  _ESC_DEFAULT="codex" ;;
  *)      _ESC_DEFAULT="ornith-cc" ;;
esac
ESCALATION_MAKER="${LOOP_ESCALATION_MAKER:-$_ESC_DEFAULT}"
DEFAULT_MAKER="${LOOP_MAKER:-qwen3-coder:30b}"   # captured at launch for cleanup/stop
N_RESTART=3; K_BREAK=4; export TASK_TIMEOUT=${TASK_TIMEOUT:-3600}
CYCLE_TIMEOUT=4500; VERIFY_TIMEOUT=1800; MIN_SLACK=1200

tree_hash(){ { git status --porcelain 2>/dev/null; git diff HEAD 2>/dev/null; } | shasum -a 256 | cut -d' ' -f1; }

# N5: push to phone via Telegram (token+chat in ~/.hermes/.env, never in the repo).
notify_phone(){ # $1=text
  [ -f "$HOME/.hermes/.env" ] || return 0
  local tok chat
  tok="$(grep -m1 '^TELEGRAM_BOT_TOKEN=' "$HOME/.hermes/.env" | cut -d= -f2-)"
  chat="$(grep -m1 '^TELEGRAM_CHAT_ID=' "$HOME/.hermes/.env" | cut -d= -f2-)"
  [ -n "$tok" ] && [ -n "$chat" ] || return 0
  # v6.65 (gap proprietaire: 2 loops en parallele = notifs indistinguables): CHAQUE message
  # est prefixe du projet. Contractuel LOOP_PROJECT_TAG (stack.sh), defaut = dossier de MAIN.
  local tag="${LOOP_PROJECT_TAG:-$(basename "$MAIN")}"
  curl -s --max-time 15 "https://api.telegram.org/bot$tok/sendMessage" \
    -d "chat_id=$chat" --data-urlencode "text=[$tag] $1" >/dev/null 2>&1 || true
}

# ================= v6.15 SENTINELLE QUOTA (mode frontier) =================
# "La lecture d'usage, uniquement quand le loop tourne frontier, juste des commandes."
# Capteur primaire: les propres appels du loop. La saturation se voit en signatures
# rate-limit dans les logs maker/checker. Crochets USAGE_CLAUDE_CMD / USAGE_CODEX_CMD
# (contrat stack) pour brancher de vraies commandes de pourcentage si disponibles.
USAGE_NOTIFIED=""
usage_watch(){ # $1=fichier log du dernier cycle
  [ "${LOOP_MAKER_KIND:-hermes}" = "hermes" ] && return 0
  local hits prov
  # v6.27.1: signatures rate-limit STRICTES (le bare "429" matchait "4294967295" d'un
  # crash dump codeSigningTrustLevel). Phrases ancrees, et on exclut le bruit de crash
  # report (trust-level, threadState, pthread_kill, pointer-free) avant de matcher.
  hits="$(grep -hiE 'rate.?limit.?exceeded|rate.?limited|\b429\b (too many|status)|too many requests|quota (exceeded|exhausted)|usage limit reached|out of (credits|quota)|retry.?after|insufficient_quota|error.?429' "$1" /tmp/lot-review-*.log 2>/dev/null \
    | grep -viE 'codeSigningTrustLevel|threadState|__pthread_kill|imageIndex|POINTER_BEING_FREED|crashed|backtrace|libmalloc' | head -3)"
  if [ -n "$hits" ]; then
    prov="${LOOP_MAKER_KIND}"
    printf '%s\t%s\t%s\n' "$(date '+%F %H:%M')" "$prov" "$(printf '%s' "$hits" | head -1 | cut -c1-160)" >> loop/reports/usage.tsv
    if [ -z "$USAGE_NOTIFIED" ]; then
      USAGE_NOTIFIED=1
      notify_phone "📉 Quota frontier sous pression ($prov): signature rate-limit dans les logs. Le loop degrade proprement (gate-only), voir loop/reports/usage.tsv"
      echo "- QUOTA: signature rate-limit detectee ($prov), voir usage.tsv" >> "$REPORT"
    fi
  fi
  # crochets optionnels du contrat: une ligne brute par fournisseur, jamais bloquant
  [ -n "${USAGE_CLAUDE_CMD:-}" ] && timeout 20 bash -c "$USAGE_CLAUDE_CMD" >> loop/reports/usage.tsv 2>/dev/null
  [ -n "${USAGE_CODEX_CMD:-}" ]  && timeout 20 bash -c "$USAGE_CODEX_CMD"  >> loop/reports/usage.tsv 2>/dev/null
  return 0
}

# ================= v6.6 FEEDBACK HUMAIN =================
# Boite aux lettres: l'humain ecrit librement dans loop/FEEDBACK.md a tout moment.
# Le loop consomme (lancement + entre cycles), trie via le maker local, cree des
# cartes 40- (01-40- si URGENT), enregistre les preferences dans DECISIONS.md,
# convoque le conseil pour l'architecture, refuse ce qui touche la loi. Verbatim
# archive dans loop/feedback/ avec la disposition de chaque item. Jamais efface.
FEEDBACK_HDR='<!-- Boite aux lettres du loop. Ecris librement, une idee par ligne ou paragraphe.
Le loop consomme au lancement et entre deux cycles, archive tout dans loop/feedback/
avec ce qu il a fait de chaque item, puis remet ce fichier a neuf.
URGENT en debut de ligne met la carte en tete de file.
La loi (loop/*.sh) ne se change pas ici, elle reste signee par git. -->'

feedback_pending(){
  [ -f loop/FEEDBACK.md ] || return 1
  grep -vE '^[[:space:]]*(<!--|-->|$)' loop/FEEDBACK.md 2>/dev/null | grep -vE '^(Le loop|URGENT en|La loi|avec ce qu)' | grep -q .
}

feedback_triage(){ # $1=texte brut -> blocs sur stdout (MLX puis ollama, sinon vide)
  PROJECT_DOMAIN="$PROJECT_DOMAIN" python3 - "$1" "${LOOP_MLX_URL:-http://localhost:1234/v1}" "${LOOP_MAKER:-qwen3-coder:30b}" <<'PYTRI'
import json, sys, urllib.request
raw, mlx, maker = sys.argv[1], sys.argv[2], sys.argv[3]
prompt = """Tu tries le feedback libre du proprietaire de: ' + __import__('os').environ.get('PROJECT_DOMAIN','une application') + ''',
pour un loop de build autonome. Pour CHAQUE item distinct du feedback, emets exactement:
===DISPO===
ITEM: <les mots de l'humain, abreges>
TYPE: BUG|PREFERENCE|SYMPTOME|ARCHITECTURE|META
ACTION: <une ligne: quelle carte creee, ou preference enregistree, ou conseil convoque, ou refuse (loi)>
===END===
Regles de type: BUG = quelque chose de casse ou non conforme. SYMPTOME = probleme constate sans
cause connue (ex: lenteur). PREFERENCE = gout, style, couleur, formulation. ARCHITECTURE = remise
en cause de structure ou d'approche. META = demande de changer le loop lui-meme ou sa loi: REFUSE,
et n'emets AUCUN bloc CARD, PREF ou COUNCIL pour un item META, seulement son DISPO.
Repete l'ouvreur ===DISPO=== pour CHAQUE item, un bloc complet par item.
Puis pour chaque BUG ou SYMPTOME (et PREFERENCE actionnable en une carte UI simple):
===CARD 40-<slug-kebab>===
# Carte, <titre court>
USE CASE:
<qui veut quoi et pourquoi, du point de vue utilisateur>
CONTEXT:
<indices utiles du feedback, verbatim inclus>
DONE WHEN:
- <critere observable 1>
- <critere observable 2 si utile>
SCOPE: front|back|full
VALUE: P1
PROBE: <UNE COMMANDE SHELL EXECUTABLE, JAMAIS une phrase. Le driver lance `bash -c` dessus:
 une phrase francaise ("Verifier que...", "Cliquer sur...", "Acceder a...", "Remplir...")
 est introuvable comme commande => echec garanti => le fix construit est REVERTE (defaut
 grave du 12/07: 30 min de travail Opus jetees). Un PROBE COMMENCE par test/rg/grep/[/(/
 cd. Prouve le CABLAGE, pas l'experience (l'e2e appartient a la passe front-review).
 Exemples: `grep -qiE "material.?symbols" frontend/src/index.html` (police
 chargee), `test -f <asset> && rg -q "<asset>" <dir>` (asset utilise), `rg -q "@media
 print" frontend/src`, `rg -q "/api/xxx" <front> && rg -q "@PostMapping"
 <back>` (cablage front+back).>
===END===
Si l'item commence par URGENT, nomme la carte 01-40-<slug> ET mets VALUE: P0 (v6.54: un
retour HUMAIN prime tout; sans VALUE le tri par valeur le fait battre par le polissage P1
du critique, defaut constate le 12/07 ou 6 cartes de defaut proprietaire ont attendu
derriere des cartes de polissage). Tout item non-urgent reste VALUE: P1 (un defaut vu par
l'humain vaut mieux qu'une amelioration devinee).
Pour chaque PREFERENCE (actionnable ou non):
===PREF===
- PREFERENCE (feedback): <la regle en une ligne> (OVERTURNABLE)
===END===
Pour chaque ARCHITECTURE:
===COUNCIL===
<le sujet, une ou deux phrases>
===END===
N'emets QUE ces blocs, rien d'autre.

FEEDBACK DE L'HUMAIN:
""" + raw
def ask(url, payload, path):
    req = urllib.request.Request(url + path, json.dumps(payload).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as r: return json.load(r)
try:
    out = ask(mlx, {"model": maker, "messages": [{"role": "user", "content": prompt}],
                    "temperature": 0.2, "max_tokens": 4000}, "/chat/completions")
    print(out["choices"][0]["message"]["content"]); sys.exit(0)
except Exception: pass
try:
    out = ask("http://localhost:11434", {"model": "qwen3-coder:30b", "prompt": prompt,
              "stream": False, "options": {"temperature": 0.2}}, "/api/generate")
    print(out.get("response", "")); sys.exit(0)
except Exception: sys.exit(0)
PYTRI
}

consume_feedback(){
  feedback_pending || return 0
  local TS ARCH RAW TRI n
  TS="$(date +%F-%H%M%S)"; ARCH="loop/feedback/archive-$TS.md"; mkdir -p loop/feedback
  RAW="$(grep -vE '^[[:space:]]*(<!--|-->)' loop/FEEDBACK.md)"
  echo "[loop] feedback humain detecte, triage local..."
  TRI="$(feedback_triage "$RAW")"
  if ! printf '%s' "$TRI" | grep -q '===DISPO==='; then
    echo "[loop] triage muet, inbox conservee pour le prochain passage"; return 0
  fi
  { echo "# Feedback humain, archive $TS"; echo; echo "## Verbatim"; echo; echo "$RAW"; echo; echo "## Dispositions"; echo; } > "$ARCH"
  printf '%s\n' "$TRI" | grep -E '^(ITEM|TYPE|ACTION):' | sed 's/^ITEM:/\n### ITEM:/' >> "$ARCH"
  # cartes 40- (01-40- si URGENT), nom valide seulement, vers tasks + queue
  printf '%s\n' "$TRI" | awk '/^===CARD /{p=$0; sub(/^===CARD /,"",p); sub(/===$/,"",p); gsub(/[^a-zA-Z0-9-]/,"",p); if (p !~ /^(01-)?40-/) {inb=0; next}; f="loop/tasks/" p ".md"; inb=1; next} /^===END===$/{if(inb){close(f)}; inb=0; next} inb{print >> f}'
  for c in loop/tasks/40-*.md loop/tasks/01-40-*.md; do
    [ -f "$c" ] || continue
    b="$(basename "$c")"
    [ -f "loop/state/queue/$b" ] || { grep -q "feedback $TS" "$c" 2>/dev/null || printf '\nSOURCE: feedback %s\n' "$TS" >> "$c"; cp "$c" "loop/state/queue/$b"; }
  done
  # preferences -> DECISIONS.md
  printf '%s\n' "$TRI" | awk '/^===PREF===$/{f=1;next} /^===END===$/{f=0} f' | grep '^- PREFERENCE' | while IFS= read -r P; do
    grep -qF -- "$P" loop/DECISIONS.md 2>/dev/null || printf '%s\n' "$P" >> loop/DECISIONS.md
  done
  # architecture -> conseil (en arriere-plan, ne bloque jamais la file)
  printf '%s\n' "$TRI" | grep -q 'TYPE: ARCHITECTURE' && printf '%s\n' "$TRI" | awk '/^===COUNCIL===$/{f=1;next} /^===END===$/{f=0} f' | grep -q . && {
    printf '%s\n' "$TRI" | awk '/^===COUNCIL===$/{f=1;next} /^===END===$/{f=0} f' > "/tmp/feedback-council-$TS.txt"
    ( bash loop/council.sh "feedback-$TS" "/tmp/feedback-council-$TS.txt" >> "loop/logs/council-feedback-$TS.log" 2>&1 || true ) &
  }
  # META refuses -> visibles au rapport du matin
  grep -B2 'TYPE: META' "$ARCH" 2>/dev/null | grep '### ITEM:' | sed 's/^### /- FEEDBACK REFUSE (loi): /' >> "$REPORT" 2>/dev/null || true
  n="$(grep -c '^### ITEM:' "$ARCH" 2>/dev/null || echo 0)"
  printf '%s\n' "$FEEDBACK_HDR" > loop/FEEDBACK.md
  git add loop/FEEDBACK.md loop/feedback loop/tasks loop/state/queue loop/DECISIONS.md >/dev/null 2>&1
  git commit -qm "loop: feedback humain consomme, $n items ($TS) [loop]" >/dev/null 2>&1 || true
  echo "- FEEDBACK: $n items consommes, archive loop/feedback/archive-$TS.md" >> "$REPORT" 2>/dev/null || true
  notify_phone "📬 Feedback consomme: $n items. Dispositions: loop/feedback/archive-$TS.md"
  echo "[loop] feedback consomme: $n items"
}
# ================= fin FEEDBACK =================

# v6.86 COUCHE DE PORTABILITE OS. La loi tournait sur des primitives BSD (date -j, date -r,
# sed -i '', stat -f): sur Linux la deadline ne se parsait meme pas. Une loi qui pretend
# etre partageable doit tourner sur l'OS de celui qui la recoit. Chaque helper essaie BSD
# puis GNU, et degrade sans jamais casser un run.
epoch_at(){ # $1 = HH:MM aujourd'hui -> epoch (BSD puis GNU)
  date -j -f "%Y-%m-%d %H:%M" "$(date +%Y-%m-%d) $1" +%s 2>/dev/null \
    || date -d "today $1" +%s 2>/dev/null
}
epoch_from_clock(){ # $1 = "2:02 PM" ou "14:02" -> epoch
  date -j -f '%I:%M %p' "$1" +%s 2>/dev/null \
    || date -j -f '%H:%M' "$1" +%s 2>/dev/null \
    || date -d "$1" +%s 2>/dev/null
}
fmt_time(){ # $1 = epoch, $2 = format optionnel -> heure lisible
  date -r "$1" ${2:+"$2"} 2>/dev/null || date -d "@$1" ${2:+"$2"} 2>/dev/null || echo '?'
}
sed_inplace(){ # sed -i portable: sed_inplace <expr> <fichier>
  sed -i '' "$@" 2>/dev/null || sed -i "$@" 2>/dev/null
}
file_size(){ stat -f %z "$1" 2>/dev/null || stat -c %s "$1" 2>/dev/null || echo 0; }
keep_awake(){ command -v caffeinate >/dev/null 2>&1 && caffeinate -i -w "$1" & }

# --- deadline -> epoch ---
now=$(date +%s)
if [[ "$DL_ARG" =~ ^\+([0-9]+)h$ ]]; then
  deadline=$(( now + ${BASH_REMATCH[1]} * 3600 ))
else
  deadline=$(epoch_at "$DL_ARG") \
    || { echo "[loop] bad deadline '$DL_ARG' (use HH:MM or +Nh)"; exit 2; }
  [ -n "$deadline" ] || { echo "[loop] bad deadline '$DL_ARG' (use HH:MM or +Nh)"; exit 2; }
  [ "$deadline" -le "$now" ] && deadline=$(( deadline + 86400 ))
fi
echo "[loop] deadline: $(fmt_time "$deadline")  base: $BASE  worktree: $WT"

[ -f "$MAIN/loop/STOP" ] && { echo "[loop] REFUSE: $MAIN/loop/STOP exists. Remove it to run."; exit 2; }

# --- preflight ---
# v6.85 (portage: ces trois gardes etaient des exigences de NOTRE projet imposees a la
# loi, donc trois REFUSE au demarrage pour quiconque n'a ni Ollama, ni PostgreSQL, ni
# macOS. Une garde d'environnement doit etre CONTRACTUELLE: on ne verifie que ce dont
# CE projet a besoin, et on ne verifie rien qui n'existe pas sur la plateforme.)
if command -v pmset >/dev/null 2>&1; then      # macOS uniquement: ailleurs, pas d'equivalent portable
  pmset -g ps | grep -q "AC Power" || { echo "[loop] REFUSE: on battery, plug in"; exit 2; }
fi
# LLM local: exige seulement si le run en utilise un (maker/juge local). LOOP_NO_LOCAL_LLM=1
# (casting frontier) ou un contrat sans LLM local sautent la garde.
if [ "${LOOP_NO_LOCAL_LLM:-0}" != 1 ] && [ "${LOOP_MAKER_KIND:-hermes}" = "hermes" ]; then
  curl -fsS "${LOCAL_LLM_HEALTH_URL:-http://localhost:11434/api/tags}" >/dev/null 2>&1 \
    || { echo "[loop] REFUSE: LLM local injoignable (${LOCAL_LLM_HEALTH_URL:-ollama}). Casting frontier? LOOP_NO_LOCAL_LLM=1"; exit 2; }
fi
# v6.2: MLX first-class. LOOP_MLX=1 => LM Studio must be serving with the model loaded
# (start server + load + pin TTL if needed); if it cannot come up, DEGRADE to ollama
# (unset LOOP_MLX) instead of refusing, the run always happens.
if [ "${LOOP_MLX:-0}" = 1 ]; then
  export PATH="$HOME/.lmstudio/bin:$PATH"
  MLXM="${LOOP_MLX_MODEL:-qwen3-coder-30b-a3b-instruct-mlx}"
  # v6.49 (regression 09/07): EXPORTER le nom et l'URL MLX pour que setup-hermes-profile
  # utilise EXACTEMENT le modele charge par le driver. Sans ca, le script profil retombait
  # sur SES defauts (nom lmstudio-community, port 8090) qui DIFFERENT des defauts driver
  # (qwen3-coder-30b-a3b-instruct-mlx, port 1234) -> profil pointe un modele/port absent ->
  # smoke echoue -> degradation. Les deux cotes doivent parler du meme modele au meme port.
  export LOOP_MLX_MODEL="$MLXM"
  export LOOP_MLX_URL="${LOOP_MLX_URL:-http://localhost:1234/v1}"
  if ! curl -fsS --max-time 3 "${LOOP_MLX_URL:-http://localhost:1234/v1}/models" >/dev/null 2>&1; then
    echo "[loop] MLX server down, starting lms server..."
    lms server start >/dev/null 2>&1; sleep 5
  fi
  # v6.26: decodage speculatif OPT-IN (LOOP_SPECULATIVE=1). Un petit draft meme-vocab
  # (Qwen3-1.7B, vocab 151936) propose des tokens que le 30B verifie: sortie identique,
  # decode plus rapide. Defaut OFF: rien ne change pour un run normal. Gain a MESURER
  # via maker-perf (le decode n'est qu'une part du temps carte, le prefill n'est pas
  # accelere). ROI reel attendu ~10-20% sur la carte, pas les 50% d'affiche du decode.
  # v6.30: garde memoire avant de charger 17Go de MLX (le crash freeze du 2026-07-07).
  # Le loop tourne normalement AFK/machine au repos, donc on AVERTIT sans bloquer (le run
  # a ete ordonne), mais on trace si la RAM est juste. LOOP_MEM_STRICT=1 pour refuser.
  [ -f loop/mem-guard.sh ] && . loop/mem-guard.sh 2>/dev/null && {
    mem_guard "${LOOP_MEM_NEED:-22}" || { [ "${LOOP_MEM_STRICT:-0}" = "1" ] && { echo "[loop] REFUSE: RAM insuffisante (LOOP_MEM_STRICT)"; rm -f "$MAIN/loop/RUNNING"; exit 2; }; notify_phone "⚠️ RAM juste au demarrage du loop, risque de swap. Ferme des apps si la machine freeze."; }
  }
  # v6.30.1: le decodage speculatif LOAD-TIME de LM Studio (--speculative-draft-simple)
  # est reserve au runtime llama.cpp/GGUF. Notre maker est MLX: son draft est prediction-
  # time, reglable UNIQUEMENT dans le GUI, pas scriptable. Donc LOOP_SPECULATIVE reste
  # inerte sur un modele MLX (injecter les flags ferait ECHOUER le load). Prouve
  # 2026-07-08: "Load-time draft speculative is only supported by the llama.cpp runtime".
  SPEC_ARGS=""
  if [ "${LOOP_SPECULATIVE:-0}" = "1" ]; then
    case "$MLXM" in
      *mlx*|*MLX*) echo "[loop] LOOP_SPECULATIVE ignore: le spec MLX est GUI-only (prediction-time), pas scriptable. Voir loop/mem-guard notes." ;;
      *) SPEC_ARGS="--speculative-draft-simple --speculative-draft-model ${LOOP_DRAFT_MODEL:-qwen/qwen3-1.7b} --speculative-draft-max-tokens ${LOOP_DRAFT_MAX:-6}"
         echo "[loop] decodage speculatif ACTIF (GGUF, draft ${LOOP_DRAFT_MODEL:-qwen/qwen3-1.7b})" ;;
    esac
  fi
  # v6.49.2 (OOM du run 022707: driver tue en cycle 1, wired 41Go/48). CAUSE: sans
  # --parallel, LM Studio charge 4 slots concurrents, chacun un KV cache de 65536 tokens
  # = ~4x la memoire KV (17Go modele + ~20Go KV = 41Go wired -> jetsam tue le driver). Le
  # loop n'execute qu'UN maker a la fois: --parallel 1 divise le KV par 4 (pic ~22Go).
  # Applique a TOUS les lms load (driver + keeper + bench), garde par harnais.
  lms ps 2>/dev/null | grep -q "$MLXM" || { echo "[loop] loading $MLXM (TTL 24h, parallel 1)..."; lms load "$MLXM" --context-length 65536 --parallel 1 --ttl 86400 $SPEC_ARGS -y >/dev/null 2>&1; }
  # ready = LOADED (lms ps) AND a real completion answers. /v1/models lists INDEXED
  # models even when nothing is loaded (that lie churned a whole run on 2026-07-05).
  MLX_OK=0
  for _try in 1 2 3; do
    # loaded AND with a big-enough context: a JIT-loaded instance defaults to ctx 8192,
    # which rejects the maker prompt ("Context length exceeded", the 17:54 stop). Evict
    # any small-context instance before trusting it.
    MLX_CTX="$(lms ps --json 2>/dev/null | python3 -c "import json,sys
try:
    for m in json.load(sys.stdin):
        if m.get('identifier')=='$MLXM': print(m.get('contextLength',0)); break
except Exception: print(0)" 2>/dev/null)"
    # v6.42: le plancher Hermes est 64000 tokens de contexte (erreur verbatim de la nuit
    # du 08/07: "below the minimum 64,000 required by Hermes Agent"). Charger a 32768
    # rendait le profil loop inadoptable -> fallback profil user -> 404 sur le nom MLX ->
    # 96 cycles muets. La SEULE config coherente: charger ET declarer 65536 partout.
    if [ -n "$MLX_CTX" ] && [ "$MLX_CTX" -lt 60000 ] 2>/dev/null && [ "$MLX_CTX" -gt 0 ] 2>/dev/null; then
      echo "[loop] MLX loaded with small context ($MLX_CTX < 65536), evicting and reloading at 65536"
      lms unload --all >/dev/null 2>&1; sleep 3
    fi
    if lms ps 2>/dev/null | grep -q "$MLXM" && [ "${MLX_CTX:-0}" -ge 60000 ] 2>/dev/null; then
      SMOKE="$(curl -s --max-time 240 "${LOOP_MLX_URL:-http://localhost:1234/v1}/chat/completions" \
        -H 'Content-Type: application/json' \
        -d '{"model":"'"$MLXM"'","messages":[{"role":"user","content":"say ok"}],"max_tokens":4}' 2>/dev/null)"
      printf '%s' "$SMOKE" | grep -q '"content"' && { MLX_OK=1; break; }
    fi
    echo "[loop] MLX not loaded yet, loading (try $_try)..."
    lms load "$MLXM" --context-length 65536 --parallel 1 --ttl 86400 -y >/dev/null 2>&1
    sleep 10
  done
  if [ "$MLX_OK" = 1 ]; then
    echo "[loop] MLX ready (loaded + completion verified): $MLXM"
    export LOOP_MAKER="${LOOP_MAKER:-$MLXM}"
    # v6.37 FIX RACINE: sous LOOP_MLX=1, le maker par defaut DOIT etre le nom MLX, pas le
    # nom ollama. Sinon la selection par carte rebascule sur qwen3-coder:30b (ollama) ->
    # hermes tape ollama (charge 18Go) EN PLUS de MLX -> deux modeles, reponses vides.
    # C'est le vrai bug de la nuit 2026-07-08 (double charge + empty). Escalade inchangee.
    DEFAULT_MAKER="$MLXM"
    # v6.2.3: keeper re-pins within 60s if LM Studio evicts/downgrades mid-run
    LOOP_MAIN_DIR="$MAIN" LOOP_MLX_MODEL="$MLXM" nohup bash "$MAIN/loop/mlx-keeper.sh" > /tmp/mlx-keeper.log 2>&1 &
    MLX_KEEPER_PID=$!
    echo "[loop] mlx-keeper watching (pid $MLX_KEEPER_PID)"
  else
    echo "[loop] WARN: MLX cannot serve, degrading to ollama for this run"
    unset LOOP_MLX
  fi
fi
# v6.85: la base de donnees est une exigence CONTRACTUELLE. DB_REQUIRED=1 (defaut pour un
# projet qui en a une, via stack.sh) verifie DB_HEALTH_CMD; un projet sans base (mobile,
# CLI, lib, front seul) ne declare rien et la garde ne s'applique pas.
if [ "${DB_REQUIRED:-0}" = 1 ]; then
  DB_HEALTH_CMD="${DB_HEALTH_CMD:-pg_isready -h localhost -p ${DB_PORT:-5432}}"
  bash -c "$DB_HEALTH_CMD" >/dev/null 2>&1 || { echo "[loop] REFUSE: base de donnees injoignable ($DB_HEALTH_CMD)"; exit 2; }
fi
git rev-parse --verify "$BASE" >/dev/null 2>&1 || { echo "[loop] REFUSE: base branch $BASE not found"; exit 2; }
git -C "$MAIN" ls-tree -r --name-only "$BASE" -- loop/tasks | grep -q '\.md$' \
  || { echo "[loop] REFUSE: no task cards committed on $BASE"; exit 2; }
lsof -ti tcp:"$BACK_PORT" >/dev/null 2>&1 && { echo "[loop] REFUSE: port $BACK_PORT busy (review backend?). Stop it first."; exit 2; }

# --- archive the PRIOR run's artifacts before recycling the worktree (review OV-4) ---
if [ -d "$WT/loop/state" ]; then
  ARCH="$MAIN/loop/archive/$(date +%Y%m%d-%H%M%S)"; mkdir -p "$ARCH"
  cp -R "$WT/loop/reports" "$ARCH/" 2>/dev/null
  cp -R "$WT/loop/logs" "$ARCH/" 2>/dev/null
  cp "$WT/loop/state/journal.md" "$ARCH/" 2>/dev/null
  echo "[loop] archived prior run artifacts -> $ARCH"
fi

# --- worktree: fresh fork from $BASE, or RESUME the existing unmerged loop branch ---
# v6.58 (13/07: refus de lancement sur worktree ORPHELINE. Le dossier existait sur disque
# mais 'git worktree list' ne le connaissait plus -> 'git worktree remove' echouait ->
# REFUS. Cause probable: app bootee depuis le worktree, metadata prune, dossier reste.
# AUTO-REPARATION: prune la metadata, puis si le dossier survit, rm -rf force. La branche
# loop/overnight (les verts) est en git, jamais dans le dossier: sa suppression est sure.)
if git worktree list | grep -q "$WT"; then
  git worktree remove --force "$WT" 2>/dev/null || true
fi
git worktree prune >/dev/null 2>&1
if [ -e "$WT" ]; then
  echo "[loop] worktree orpheline detectee, auto-nettoyage (rm -rf, branche preservee en git)"
  rm -rf "$WT" 2>/dev/null
  [ -e "$WT" ] && { echo "[loop] REFUSE: worktree $WT indelogeable (verrou externe? app encore bootee?)"; exit 2; }
fi
RESUMED=0
if git rev-parse --verify loop/overnight >/dev/null 2>&1; then
  if [ -n "$(git log "$BASE"..loop/overnight --oneline 2>/dev/null)" ]; then
    if [ "${LOOP_RESUME:-1}" = "1" ]; then
      git worktree add "$WT" loop/overnight >/dev/null 2>&1 || { echo "[loop] REFUSE: worktree resume failed"; exit 2; }
      RESUMED=1
      echo "[loop] RESUMING loop/overnight ($(git log --oneline "$BASE"..loop/overnight | wc -l | tr -d ' ') commits ahead of $BASE)"
    else
      arch="loop/overnight-$(date +%Y%m%d-%H%M%S)"; git branch -m loop/overnight "$arch"
      echo "[loop] archived prior loop branch as $arch"
    fi
  else
    git branch -D loop/overnight >/dev/null
  fi
fi
[ "$RESUMED" = "0" ] && { git worktree add -b loop/overnight "$WT" "$BASE" >/dev/null 2>&1 || { echo "[loop] REFUSE: worktree add failed"; exit 2; }; }
cd "$WT"
# v6.50.2 (pilote bug structurel #1: loop/overnight vit sa propre lignee et ne recoit
# JAMAIS les commits faits sur dev entre les runs => cartes semees, loi resyncee et
# archivages faits sur dev INVISIBLES au run, et merge retour non-ff). Au RESUME, on fait
# entrer $BASE dans la branche du run: la LOI et les CARTES (loop/) suivent dev (autorite
# du semis et de la loi), le CODE PRODUIT (BACK_DIR/FRONT_DIR) suit le run (verts en cours).
# Sur un fresh-fork (RESUMED=0) la branche vient deja de $BASE, rien a faire.
if [ "$RESUMED" = "1" ]; then
  if git merge --no-edit "$BASE" >/dev/null 2>&1; then
    echo "[loop] resume: dev fusionne proprement dans loop/overnight (loi + cartes a jour)"
  else
    git checkout --theirs -- loop/constitution.md loop/*.sh loop/hints.d loop/skills-front loop/carto-lenses.md loop/tasks 2>/dev/null
    [ -n "$BACK_DIR" ] && git checkout --ours -- "$BACK_DIR" 2>/dev/null
    [ -n "$FRONT_DIR" ] && git checkout --ours -- "$FRONT_DIR" 2>/dev/null
    git add -A 2>/dev/null
    if git commit --no-edit >/dev/null 2>&1; then
      echo "[loop] resume: dev fusionne avec resolution (loi/cartes<-dev, produit<-run)"
    else
      git merge --abort 2>/dev/null
      echo "[loop] resume: fusion dev impossible, re-fork PROPRE depuis $BASE (etat run abandonne pour la verite dev)"
      cd "$MAIN"; git worktree remove --force "$WT" 2>/dev/null; git branch -D loop/overnight 2>/dev/null
      git worktree add -b loop/overnight "$WT" "$BASE" >/dev/null 2>&1 || { echo "[loop] REFUSE: re-fork failed"; exit 2; }
      cd "$WT"; RESUMED=0
    fi
  fi
fi
echo "[loop] worktree ready on branch $(git branch --show-current) (base $BASE, resumed=$RESUMED)"
[ -x loop/run-cycle.sh ] || { echo "[loop] REFUSE: loop/run-cycle.sh missing in worktree"; exit 2; }

# v6.43 (portabilite): install des dependances via le CONTRAT, plus de npm en dur dans
# la loi. Sur un stack sans STACK_INSTALL_CMD ni package.json (api-only .NET, lib PHP...),
# on ne tente RIEN au lieu de refuser le lancement (l'ancien npm ci en dur aurait fait
# "REFUSE" sur tout projet non-node: une nuit blanche de classe v6.42, cote stack).
_INST_SENTINEL="${STACK_INSTALL_SENTINEL:-$FRONT_DIR/node_modules}"
_INST_CMD="${STACK_INSTALL_CMD:-}"
[ -z "$_INST_CMD" ] && [ -f "$FRONT_DIR/package.json" ] && _INST_CMD="cd '$FRONT_DIR' && npm ci --no-audit --no-fund"   # stack-default (v6.73: plus de --silent, le log d'install doit porter l'erreur npm reelle)
if [ -n "$_INST_CMD" ] && [ ! -e "$_INST_SENTINEL" ]; then
  echo "[loop] install deps ($STACK_NAME, one-time)..."
  ( timeout 900 bash -c "$_INST_CMD" ) >/tmp/$(basename "$MAIN")-install.log 2>&1 \
    || { echo "[loop] REFUSE: install deps failed"; tail -15 /tmp/$(basename "$MAIN")-install.log; exit 2; }
fi

# --- v5.9: loop-scoped Hermes profile (N2 write-boundary hook, N4 fallback, N6 memory) ---
# Adopted ONLY if its PONG smoke passes. v6.42: sous LOOP_MLX=1, le profil user n'est PAS
# une degradation gracieuse, c'est une nuit blanche garantie: il ne connait pas le nom du
# modele MLX, donc CHAQUE appel maker repond "HTTP 404: model not found" et hermes sort
# exit=0 sans rien ecrire (96 cycles a vide le 08/07). Sous MLX, un smoke de profil qui
# echoue est une panne INFRA au lancement: on re-essaie (recharge modele entre les essais),
# et si le profil reste inadoptable on DEGRADE PAR SWAP vers ollama-primaire (un seul
# modele resident, doctrine v6.36), le seul mode que le profil user sait servir.
unset LOOP_HERMES_HOME
if [ "${LOOP_HERMES_PROFILE:-1}" = 1 ]; then
  for _ptry in 1 2 3; do
    if bash loop/setup-hermes-profile.sh "$WT"; then
      export LOOP_HERMES_HOME="${LOOP_PROFILE_DIR:-$HOME/.hermes-loop-cdc}"
      echo "[loop] maker sessions use the loop Hermes profile (hook+fallback+memory)"
      break
    fi
    if [ "${LOOP_MLX:-0}" = 1 ] && [ "$_ptry" -lt 3 ]; then
      echo "[loop] profil loop KO (essai $_ptry/3) sous MLX: recharge modele a 65536 puis retry"
      lms unload --all >/dev/null 2>&1; sleep 3
      lms load "$MLXM" --context-length 65536 --parallel 1 --ttl 86400 -y >/dev/null 2>&1; sleep 5
      continue
    fi
    if [ "${LOOP_MLX:-0}" = 1 ] && [ "${LOOP_ALLOW_OLLAMA_FALLBACK:-0}" = 1 ]; then
      echo "[loop] DEGRADATION SWAP: profil loop inadoptable sous MLX apres 3 essais."
      echo "[loop] Bascule ollama-primaire (profil user compatible), MLX decharge."
      lms unload --all >/dev/null 2>&1
      export LOOP_MLX=0
      DEFAULT_MAKER="${LOOP_FALLBACK_PRIMARY:-qwen3-coder:30b}"
      export LOOP_MAKER="$DEFAULT_MAKER"
      notify_phone "⚠️ Profil loop inadoptable sous MLX (3 essais): nuit degradee en ollama-primaire ($DEFAULT_MAKER). Le loop continue."
    elif [ "${LOOP_MLX:-0}" = 1 ]; then
      # v6.49 (regle proprietaire du 09/07: "dont launch ollama"): sous MLX, un profil
      # inadoptable est une PANNE DE LANCEMENT, pas un pretexte a lancer ollama en douce
      # (ollama-primaire viole la regle dure MLX). On REFUSE le run, bruyamment, avec la
      # cause: l'operateur repare le profil (souvent la config hermes de base a change) et
      # relance. Jamais de nuit ollama silencieuse. Reactivable via LOOP_ALLOW_OLLAMA_FALLBACK=1.
      echo "[loop] REFUSE: profil loop MLX inadoptable apres 3 essais et ollama interdit (regle proprietaire)."
      echo "[loop] Cause probable: config hermes de base incompatible (provider moa?), pyyaml absent, ou modele/port MLX errone."
      lms unload --all >/dev/null 2>&1
      rm -f "$MAIN/loop/RUNNING"
      notify_phone "⛔ REFUS lancement ($(basename "$MAIN")): profil maker MLX inadoptable (3 essais), ollama interdit. Repare le profil et relance. AUCUNE nuit ollama."
      exit 2
    else
      echo "[loop] WARN: loop profile smoke failed, maker sessions use the user profile"
    fi
    break
  done
fi

# --- runtime state ---
mkdir -p loop/state loop/reports loop/logs loop/state/done loop/state/failed
# v6.50.4 (pilote, "line 553: REPORT: unbound variable" sur un FRONT vide au demarrage:
# la branche socle-front ecrit >>"$REPORT" au SEMIS, mais REPORT n'etait assigne qu'a la
# ligne ~873, apres le semis => crash set -u, run mort avant le cycle 1, au PIRE moment,
# un projet neuf au front legitimement vide. Nieme recidive def-avant-usage (run-cycle:427,
# OUT). REPORT/RUN existent desormais AVANT toute phase qui peut y ecrire (socle, quota,
# feedback). L'assignation tardive garde RUN_T0 (chrono de run) mais ne re-timestampe plus.)
RUN="$(date +%Y%m%d-%H%M%S)"; REPORT="loop/reports/report-$RUN.md"
rm -rf loop/state/.lot-review.lock   # v6.2: stale lock from a crashed run never blocks
rm -rf loop/state/queue; mkdir -p loop/state/queue
base_name(){ local n="$1" p
  while :; do p="$n"
    n="${n#zz-E-}"; n="${n#zz-D-}"; n="${n#zz-H-}"
    [ "$n" = "$p" ] && break
  done
  echo "$n"
}

# v6.41 (verdict pilote, 3 runs, 2 makers: le front ne se construit JAMAIS).
# Cause triple: la carte de conformite front est trop grosse pour un pass (page+routing+
# client HTTP+composant), la lentille FONDATION-FRONT ne fire pas (le carto priorise le
# back), et DEFER-HARD en boucle ne declenche ni split ni scaffold. Reponse MECANIQUE:
# si le dossier pages est quasi vide ET qu'une carte scope=front attend, on INJECTE une
# carte socle (routing + client HTTP + UNE page reelle branchee sur un endpoint existant)
# et on suspend les cartes front derriere elle par DEPENDS. Deterministe, zero priere.
# (Definie AVANT le premier semis qui l'appelle: lecon base_name v6.8.2, 3e recidive.)
sanitize_cards(){ # v6.50.7 (remontee proprietaire: les cartes sont fabriquees par des
  # ORGANES (distiller, carto, critic); le distiller emettait des probes en code-span
  # markdown `...` => substitution bash => echec garanti, 3 faux negatifs le 10/07, 18min
  # d analyse detruite). TOUT fabricant passe par CET assainisseur a la naissance: les
  # lignes PROBE perdent puces et backticks, redeviennent des commandes brutes.
  local q
  for q in loop/state/queue/*.md loop/tasks/*.md; do
    [ -f "$q" ] || continue
    if grep -qE '^PROBE: *`|^- *`' "$q" 2>/dev/null; then
      sed -i '' -E 's/^PROBE: *`(.*)`[[:space:]]*$/PROBE: \1/' "$q" 2>/dev/null
      echo "[loop] sanitize: probes markdown normalisees dans $(basename "$q" .md)"
    fi
  done
  return 0
}
runnable_probes(){ # v6.56 AUTO-REPARATION du construire-et-reverter (defaut 12/07: des
  # PROBE en prose "Verifier que..." revertaient du bon code). Ne rend QUE les probes
  # EXECUTABLES d'une carte: strip "PROBE: " et backticks markdown, JETTE toute ligne en
  # prose (commence par un verbe naturel) ou vide. Une carte dont TOUTES les probes sont
  # jetees se comporte comme une carte sans probe: jugee par le gate + le checker seuls,
  # le bon code passe vert au lieu d'etre reverte. Le loop se soigne et CONTINUE, pas de
  # pause (pauser une nuit = nuit perdue pareil, regle proprietaire).
  local line p
  while IFS= read -r line; do
    p="${line#PROBE: }"; p="${p#\`}"; p="${p%\`}"
    [ -z "$p" ] && continue
    if printf '%s' "$p" | grep -qiE '^ *(verifier|v\xc3\xa9rifier|cliquer|acceder|acc\xc3\xa9der|remplir|ouvrir|naviguer|ensure|check|verify|confirm|make sure|s.assurer)'; then
      echo "[loop] probe non-executable NEUTRALISEE (prose, aurait reverte du bon code): $p" >&2
      continue
    fi
    # v6.57.1 (recidive 12/07 par une carte CARRIED d'avant le fix: rg -qiE = rc=2
    # 'unknown encoding', 21min de PV revertes une 2e fois): le filtre lexical ne voit pas
    # une commande VALIDE EN APPARENCE mais malformee. DRY-RUN: rc>=2 hors timeout = la
    # commande elle-meme est cassee (flag/parse/introuvable), jamais verdissable =>
    # NEUTRALISEE a l'execution aussi. rc=0/1 = saine (match ou echec legitime).
    ( timeout 20 bash -c "$p" ) >/dev/null 2>&1; _rrc=$?
    if [ "$_rrc" -ge 2 ] && [ "$_rrc" != 124 ] && [ "$_rrc" != 1 ]; then
      echo "[loop] probe MALFORMEE NEUTRALISEE (rc=$_rrc, jamais verdissable): $p" >&2
      continue
    fi
    printf '%s\n' "$p"
  done < <(grep '^PROBE: ' "$1" 2>/dev/null)
}
card_has_or_probes(){ # v6.71 (pilote 17/07: WARN probe-lint sans effet, AUTODONE menteur
  # 40 min apres sur `rg A || rg B` dont le 2e membre etait vrai depuis le design v1).
  # rc 0 = la carte porte au moins un probe OU: alternance '|' dans un pattern rg/grep
  # quote OU '||' shell entre commandes. Un OU peut etre vrai AVANT la feature => la
  # carte ne peut PAS etre AUTODONE (ni au pick ni en LATE), elle doit passer par un
  # cycle maker + gate. Le lint detecte, cette fonction APPLIQUE.
  # Detection TEXTUELLE (grep des lignes PROBE brutes, pas runnable_probes qui
  # dry-run/execute chaque probe: cher, et neutralise rc>=2 donc aveugle ici).
  local l
  while IFS= read -r l; do
    [ -z "$l" ] && continue
    case "$l" in
      *"||"*) return 0 ;;
      *rg*\"*\|*\"*|*grep*\"*\|*\"*) return 0 ;;
    esac
  done < <(grep '^PROBE: ' "$1" 2>/dev/null)
  return 1
}
ensure_front_scaffold(){
  local pages fcards _ext
  # v6.45 (BUG A pilote): ${VAR%% *} sur variable ABSENTE crashe sous set -u AVANT le
  # garde-fou. Toujours defaulter (:-) AVANT de trancher (%%).
  _ext="${EYE_SRC_EXTS:-ts java}"; _ext="${_ext%% *}"   # stack-default
  # v6.43: n'a de sens que si l'architecture a un front (contrat ARCH_PROFILE). Sur un
  # projet api-only/lib/cli, injecter une carte "routing + page" serait un non-sens force.
  case "${ARCH_PROFILE:-web-fullstack}" in api-only|lib|cli) return 0 ;; esac
  pages="$(ls "$EYE_PAGES_DIR" 2>/dev/null | wc -l | tr -d ' ')"
  [ "${pages:-0}" -ge 2 ] && return 0
  fcards="$(grep -l '^SCOPE: front' loop/state/queue/*.md 2>/dev/null | grep -v 'front-scaffold' | head -5)"
  [ -z "$fcards" ] && return 0
  git log --format=%s "$BASE" 2>/dev/null | grep -q '^feat: 05-front-scaffold \[loop' && return 0
  # v6.43.1 (observation pilote, run 11:38): le carto peut avoir ecrit SA carte socle
  # (regle prompt pages<2). Ne JAMAIS injecter un doublon (deux socles = churn sur le meme
  # routing); suspendre les cartes front derriere le socle EXISTANT quel que soit son nom.
  # Avant: DEPENDS pointait en dur sur 05-front-scaffold, jamais arme si le socle venait
  # du carto, et l'ordre ne tenait que par chance alphabetique (50-socle < 50-tableau).
  local socle sbase
  socle="$(grep -liE 'SOCLE FRONT|socle du front' loop/state/queue/*.md 2>/dev/null | grep -v '05-front-scaffold' | head -1)"
  [ -z "$socle" ] && socle="$(ls loop/state/queue/*.md 2>/dev/null | grep -iE 'socle|fondation|scaffold' | grep -v '05-front-scaffold' | head -1)"
  if [ -n "$socle" ]; then
    sbase="$(base_name "$(basename "$socle" .md)")"
    for f in $fcards; do
      [ "$f" = "$socle" ] && continue
      grep -q '^DEPENDS:' "$f" 2>/dev/null || printf 'DEPENDS: %s\n' "$sbase" >> "$f"
    done
    echo "[loop] SOCLE FRONT du carto detecte ($sbase): cartes front suspendues derriere lui, pas d'injection"
    return 0
  fi
  if [ ! -f loop/state/queue/05-front-scaffold.md ]; then
    cat > loop/state/queue/05-front-scaffold.md <<SCAF
# Carte, socle front (injectee mecaniquement: pages=$pages, cartes front en attente)

USE CASE:
Le front est un squelette vide et des cartes d'ecran attendent. AUCUN ecran ne peut
exister sans socle. Construis le MINIMUM vital du front, dans $FRONT_DIR: le routing
racine reel, le client HTTP configure, et UNE page reelle (la page d'accueil) qui
consomme UN endpoint existant du back et affiche ses donnees. Remplace le placeholder.
Suis les idiomes du projet (voir le brief stack de ta constitution).
IMPORTANT: en remplacant le shell par defaut, METS A JOUR (ou remplace) les tests par
defaut du squelette qui le decrivent (ex: app.spec, widget_test): un spec par defaut
laisse tel quel casse la suite de tests alors que ton socle est correct (piege releve
sur 5 echecs du loop pilote, 2026-07-08).

DONE WHEN:
- Une page reelle rend des donnees venant du back (pas de donnees en dur).
- Le routing racine mene a cette page; le build front passe.
- Les tests par defaut du squelette modifies sont a jour (aucun spec ne decrit l'ancien shell).

SCOPE: front
VALUE: P1
PROBE: test "\$(ls $EYE_PAGES_DIR 2>/dev/null | wc -l | tr -d ' ')" -ge $(( pages + 1 ))
PROBE: grep -rq "http" $EYE_FRONT_SRC --include='*.$_ext' -i
PROBE: grep -rqi "rout" $EYE_FRONT_SRC --include='*.$_ext'
SCAF
    echo "[loop] SOCLE FRONT injecte (pages=$pages, $(printf '%s\n' "$fcards" | wc -l | tr -d ' ') carte(s) front en attente)"
    echo "- SOCLE FRONT injecte mecaniquement (front vide + cartes front en file)" >> "$REPORT"
  fi
  # les cartes front sans DEPENDS attendent le socle (le DAG les differe)
  for f in $fcards; do
    grep -q '^DEPENDS:' "$f" 2>/dev/null || printf 'DEPENDS: 05-front-scaffold\n' >> "$f"
  done
  return 0
}

# v6.45 (quota pilote 08/07: codex epuise a 12:38 -> le loop ne savait PLUS generer
# de cartes meme avec un quota claude frais). Le CERVEAU DES CARTES (revue de semis,
# refill carto, decoupage des parkees) passait par codex EN DUR. Miroir de COUNCIL_CHAIR:
# LOOP_CARTO_CHAIR=codex (defaut) | claude, et l'AUTRE famille est le fallback automatique
# quand la primaire est muette (quota/panne). Le checker de lot reste codex (independance
# juge/maker, doctrine inchangee): un quota codex mort defere les verdicts, mais ne gele
# plus la GENERATION de cartes.
carto_llm(){ # $1=timeout-s  $2=prompt  -> texte sur stdout ('' si les deux familles muettes)
  local to="$1" p="$2" out="" primary="${LOOP_CARTO_CHAIR:-codex}"
  # v6.50 (routing par role): la QUALITE des cartes est la contrainte qui lie l'honnetete
  # du maker (une carte a probes laches = green creux). LOOP_CARTO_MODEL choisit le modele
  # du cerveau des cartes; RIEN en dur, defaut = modele CLI par defaut de chaque famille.
  if [ "$primary" = "claude" ] && command -v claude >/dev/null 2>&1; then
    out="$(timeout "$to" claude ${LOOP_CARTO_MODEL:+--model "$LOOP_CARTO_MODEL"} -p "$p" --output-format text 2>/dev/null)"
    [ -n "$out" ] && { printf '%s' "$out"; return 0; }
  fi
  out="$(timeout "$to" codex exec --sandbox read-only --skip-git-repo-check ${LOOP_CARTO_MODEL:+-m "$LOOP_CARTO_MODEL"} "$p" 2>/dev/null)"
  if [ -z "$out" ] && [ "$primary" != "claude" ] && command -v claude >/dev/null 2>&1; then
    printf -- '- [carto] codex muet (quota/panne): bascule claude\n' >> "${JOURNAL:-/dev/null}" 2>/dev/null
    out="$(timeout "$to" claude -p "$p" --output-format text 2>/dev/null)"
  fi
  printf '%s' "$out"
}

cp loop/tasks/*.md loop/state/queue/
# v6.38 FIX A (nuit 2026-07-08): dedup UNIVERSELLE au semis. Une carte deja verte dans
# l'historique ET sans PROBE (fix-lot residuelle type 91-fix-critical, verte 4x) ne peut
# ni etre AUTODONE (pas de probe) ni etre dedup'ee par v6.2.8 (motifs 00-F*/zz-E* seuls).
# Elle empoisonne chaque run: maker no-change -> faux positif infra -> boucle de pause.
for q in loop/state/queue/*.md; do
  [ -f "$q" ] || continue
  qn="$(basename "$q" .md)"
  if ! grep -q '^PROBE' "$q" 2>/dev/null && git log --format=%s "$BASE" 2>/dev/null | grep -q "^feat: $(base_name "$qn") \[loop"; then
    rm -f "$q"; echo "[loop] seed-dedup: $qn deja vert et sans probe, retire de la file"
    continue
  fi
  # v6.83 (regression de v6.81, vue au run post-merge du 27/07): la dedup ci-dessus ne
  # traite QUE les cartes sans probe, parce qu'AVANT v6.81 une carte de reparation deja
  # faite sortait de la file par AUTODONE. v6.81 a ferme cette porte (a raison: des probes
  # verts sur une reparation sont des probes suspects) mais sans ouvrir l'autre: ces cartes
  # ne sortaient plus JAMAIS seules et revenaient a chaque run bruler un cycle pour finir
  # en no-change. Ici la preuve n'est pas la probe, c'est l'HISTORIQUE: un commit
  # 'feat: <carte> [loop' signifie que le gate a valide ce travail et qu'il est dans la base.
  case "$(base_name "$qn")" in
    00-F*|00-E2E*|zz-E-*)
      if git log --format=%s "$BASE" 2>/dev/null | grep -q "^feat: $(base_name "$qn") \[loop"; then
        rm -f "$q"; echo "[loop] seed-dedup: $qn (reparation) deja verte dans l'historique de $BASE, retiree de la file"
      fi ;;
  esac
done
sanitize_cards
ensure_front_scaffold
# v6.44 lint probes (diagnostic pilote: LE mur front): une carte d'ECRAN front dont
# le PROBE exige un test unitaire ecrit par le maker (npm test / ng test) cale les
# makers en boucle (spec TestBed fragile + revert atomique). On previent, on ne casse
# rien: la carte finira DEFER-HARD x2 -> PARK -> le carto la redecoupe avec les regles
# probes v6.44 (build + rg cablage + e2e).
for q in loop/state/queue/*.md; do
  [ -f "$q" ] || continue
  if grep -q '^SCOPE: front' "$q" 2>/dev/null && grep -qE '^PROBE.*(npm test|ng test)' "$q" 2>/dev/null; then
    echo "[loop] WARN probe-lint: $(basename "$q" .md) (ecran front) exige un test unitaire maker-authored: piege TestBed connu, candidate au redecoupage carto"
  fi
  # v6.48 (remontee 20 pilote): un rg/grep a alternance 3+ tokens est un OU qui MENT
  # (un seul token generique deja present => carte nee 'satisfaite' => AUTODONE menteur,
  # l'ecran n'est jamais construit). WARN bruyant: le carto regenerera en probes-ET.
  if grep -qE '^PROBE:.*playwright' "$q" 2>/dev/null; then
    echo "[loop] WARN probe-lint: $(basename "$q" .md) porte une jambe playwright en PROBE (inexecutable: sandbox sans port, driver a timeout court): elle sera SAUTEE inline, l'execution appartient a la phase e2e"
  fi
  # v6.55 (defaut 12/07: cartes feedback a PROBE en PROSE => faux rouge => fix reverte).
  # Un PROBE qui commence par un verbe naturel (Verifier/Cliquer/Acceder/Remplir/Ensure/
  # Check/Verify/Ensure) au lieu d'une commande shell est INEXECUTABLE: echec garanti.
  if grep -qiE '^PROBE: *(verifier|cliquer|acceder|acc\xc3\xa9der|remplir|ouvrir|ensure|check|verify|confirm|s.assurer)' "$q" 2>/dev/null; then
    echo "[loop] WARN probe-lint: $(basename "$q" .md) porte un PROBE EN PROSE (commence par un verbe, pas une commande): faux rouge garanti, le fix serait reverte. A reecrire en commande (test/rg/grep)."
  fi
  # v6.56.1 (rg -E = ENCODING chez ripgrep, pas extended-regex: rc=2 'unknown encoding',
  # rouge A VIE, 19min de travail PV-comite reverte le 12/07): DRY-RUN de chaque probe au
  # semis. rc=0/1 = sain (match ou echec legitime attendu avant construction); rc>=2 ou
  # 127 = COMMANDE MALFORMEE (erreur de parsing/flag/introuvable), jamais verdissable.
  while IFS= read -r _pl; do
    [ -z "$_pl" ] && continue
    ( timeout 20 bash -c "$_pl" ) >/dev/null 2>&1; _prc=$?
    if [ "$_prc" -ge 2 ] && [ "$_prc" != 124 ]; then
      echo "[loop] WARN probe-lint: $(basename "$q" .md) probe MALFORMEE (rc=$_prc, jamais verdissable): $_pl"
    fi
  done < <(runnable_probes "$q")
  # v6.71: detection elargie (alternance simple '|' dans un pattern quote, ou '||' shell)
  # et surtout EFFET REEL: card_has_or_probes interdit l'AUTODONE aux deux points d'entree.
  if card_has_or_probes "$q"; then
    echo "[loop] WARN probe-lint: $(basename "$q" .md) porte un probe OU (alternance pattern ou || shell = OU menteur): AUTODONE INTERDIT pour cette carte, elle passera par maker + gate"
  fi
done
# v6.2.5: one-shot carry of fix-lot cards across run boundaries (a fresh fork must not
# lose a lot review's findings that fired near the previous run's deadline)
if ls "$MAIN"/loop/wip/queue-carry/*.md >/dev/null 2>&1; then
  # v6.50 (pilote): ne PAS re-semer une carte portee dont le lot d'origine est deja
  # merge dans dev (elle AUTODONE ou green-trivial et brule 1-2 cycles en tete de chaque
  # run). Si sa feature de base est verte dans l'historique, on la jette au lieu de la porter.
  for _cc in "$MAIN"/loop/wip/queue-carry/*.md; do
    [ -f "$_cc" ] || continue
    _ccb="$(base_name "$(basename "$_cc" .md)")"
    if git log --format=%s "$BASE" 2>/dev/null | grep -q "^feat: $_ccb \[loop"; then
      echo "[loop] carry-drop: $(basename "$_cc" .md) (lot d'origine deja merge, pas de re-semis)"
      rm -f "$_cc"
    else
      cp "$_cc" loop/state/queue/ && rm -f "$_cc"
    fi
  done
  echo "[loop] carried fix-lot cards (non deja-merges) into the queue"
fi
perf_log(){ # $1=verdict $2=secondes  -- debit du maker par famille, mesure objective
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$RUN" "$COMMIT_NAME" "${PERF_KIND:-?}" "${PERF_MODEL:-?}" "$2" "$1" "spec=${LOOP_SPECULATIVE:-0}" >> "$MAIN/loop/reports/maker-perf.tsv"
}
# v6.36 SWAP: UN SEUL modele local resident a la fois. Pour un maker ollama (escalade
# ornith), on DECHARGE MLX + on met le keeper en pause; ollama charge le modele a la
# demande. Au cycle MLX suivant, on decharge l'ollama + on recharge MLX + on relance le
# keeper. Jamais deux LLM locaux ensemble (48Go memoire unifiee = crash). C'est le swap,
# comme ollama gere ses propres modeles. Cause: nuit 2026-07-08, MLX 17Go + ornith 26Go.
MLX_KEEPER_PID="${MLX_KEEPER_PID:-}"
model_alive(){
  # v6.46.1 (incident 08/07, 17h: le release-smoke a CHARGE qwen3-coder 21Go sur le GPU
  # pendant que l'utilisateur travaillait). Cette sonde fait un generate: sur ollama,
  # generate CHARGE le modele. LOOP_NO_LOCAL_LLM=1 rend TOUTE la couche modele inerte
  # (sonde=vrai, heal/swap/police=no-op): les tests de loi ne touchent JAMAIS au GPU.
  [ "${LOOP_NO_LOCAL_LLM:-0}" = 1 ] && return 0 # la couche du MAKER courant repond-elle a une VRAIE completion?
  if [ "${LOOP_MLX:-0}" = 1 ]; then
    curl -s --max-time 30 "${LOOP_MLX_URL:-http://localhost:1234/v1}/chat/completions" -H 'Content-Type: application/json' \
      -d "{\"model\":\"$MLXM\",\"messages\":[{\"role\":\"user\",\"content\":\"ok\"}],\"max_tokens\":2}" 2>/dev/null | grep -q '"content"'
  else
    curl -s --max-time 30 http://localhost:11434/api/generate \
      -d "{\"model\":\"$DEFAULT_MAKER\",\"prompt\":\"ok\",\"stream\":false,\"options\":{\"num_predict\":2}}" 2>/dev/null | grep -q '"response"'
  fi
}

heal_model_layer(){ # v6.39: l'auto-reparation que l'operateur faisait a la main la nuit du 08/07
  [ "${LOOP_NO_LOCAL_LLM:-0}" = 1 ] && return 0   # v6.46.1: couche modele inerte (tests)
  echo "[loop] HEAL: tentative de reparation de la couche modele..."
  if [ "${LOOP_MLX:-0}" = 1 ]; then
    lms server start >/dev/null 2>&1; sleep 5
    lms ps 2>/dev/null | grep -q "$MLXM" || lms load "$MLXM" --context-length 65536 --parallel 1 --ttl 86400 -y >/dev/null 2>&1
  else
    curl -fsS --max-time 3 http://localhost:11434/api/tags >/dev/null 2>&1 || { open -a Ollama 2>/dev/null; sleep 8; }
  fi
  model_alive && { echo "[loop] HEAL: couche modele reparee"; return 0; }
  echo "[loop] HEAL: toujours morte"; return 1
}

mem_police(){ # v6.39: sous MLX, aucun modele ollama ne doit rester residant (2 LLM = crash 48Go)
  [ "${LOOP_NO_LOCAL_LLM:-0}" = 1 ] && return 0   # v6.46.1: couche modele inerte (tests)
  [ "${LOOP_MLX:-0}" = 1 ] || return 0
  local loaded
  loaded="$(curl -s --max-time 3 http://localhost:11434/api/ps 2>/dev/null | python3 -c "import json,sys
try: print(' '.join(m.get('name','') for m in json.load(sys.stdin).get('models',[])))
except Exception: pass" 2>/dev/null)"
  for m in $loaded; do
    echo "[loop] mem-police: decharge $m (un seul modele local sous MLX)"
    curl -s --max-time 15 http://localhost:11434/api/generate -d "{\"model\":\"$m\",\"keep_alive\":0}" >/dev/null 2>&1
    ollama stop "$m" 2>/dev/null
  done
  return 0
}

swap_local(){ # $1 = maker de ce cycle
  [ "${LOOP_NO_LOCAL_LLM:-0}" = 1 ] && return 0 # v6.46.1: couche modele inerte (tests)
  [ "${LOOP_MLX:-0}" = 1 ] || return 0          # swap seulement en mode MLX primaire
  command -v lms >/dev/null 2>&1 || return 0
  case "$1" in
    *mlx*|*MLX*)
      # MLX doit etre resident: decharger tout ollama, (re)charger MLX, keeper actif
      ollama stop "$DEFAULT_MAKER" 2>/dev/null; ollama stop "$ESCALATION_MAKER" 2>/dev/null
      curl -s --max-time 20 "http://localhost:11434/api/generate" -d "{\"model\":\"$ESCALATION_MAKER\",\"keep_alive\":0}" >/dev/null 2>&1
      lms ps 2>/dev/null | grep -q "$MLXM" || lms load "$MLXM" --context-length 65536 --parallel 1 --ttl 86400 -y >/dev/null 2>&1
      if [ -z "$MLX_KEEPER_PID" ] || ! kill -0 "$MLX_KEEPER_PID" 2>/dev/null; then
        LOOP_MAIN_DIR="$MAIN" LOOP_MLX_MODEL="$MLXM" nohup bash "$MAIN/loop/mlx-keeper.sh" > /tmp/mlx-keeper.log 2>&1 &
        MLX_KEEPER_PID=$!
      fi ;;
    *)
      # maker ollama (ex ornith): liberer MLX + arreter le keeper (sinon il re-pin MLX)
      [ -n "$MLX_KEEPER_PID" ] && kill "$MLX_KEEPER_PID" 2>/dev/null; MLX_KEEPER_PID=""
      lms unload --all >/dev/null 2>&1; sleep 1
      echo "[loop] SWAP -> $1 (MLX decharge, un seul modele local a la fois)" ;;
  esac
}
esc_family(){ case "$1" in *mlx*|*MLX*) echo mlx;; claude-*|*opus*|*sonnet*|*haiku*) echo claude;; codex|gpt-*|o1-*|o3-*|o4-*) echo codex;; *) echo hermes;; esac; }

# ===== v6.46 PREFLIGHT DE CHAINE (cahier des charges pilote, points 2/4/5) =====
# 8 fenetres consommateur perdues sur des defauts de HARNAIS, jamais sur le produit.
# Avant de bruler une fenetre: contrat imprime et valide, gate auto-teste sur l'arbre
# CONNU-BON (le fork vient de la base qui compile), un ping par organe LLM, quotas
# visibles. Tout organe mort = REFUS a la minute ~2 avec la cause exacte, pas un run
# fantome de 60 minutes. Le REFUS au LANCEMENT protege la fenetre; le never-stop v6.39
# reste la loi EN run (jamais d'arret avant deadline une fois les cycles commences).
# LOOP_DRYBOOT=1: s'arrete apres le preflight, exit 0 (verifier une config sans nuit).
# LOOP_PREFLIGHT_SKIP_LLM=1: saute les pings maker/carto (release-smoke, projet jouet).
print_contract(){ # point 4: la config EFFECTIVE, valeur + provenance, zero etat cache
  local v val src
  echo "[preflight] loi: $(git -C "$MAIN" log -1 --format='%h' -- loop/ 2>/dev/null || echo '?')  snapshot: $(shasum "$0" 2>/dev/null | cut -c1-12)"
  for v in STACK_NAME ARCH_PROFILE BACK_DIR FRONT_DIR BACK_PORT GATE_FRONT_CMD GATE_BACK_CMD STACK_INSTALL_CMD TOOLCHAIN_HINT EYE_SRC_EXTS EYE_ENTITY_EXT E2E_SENTINEL HEALTH_OK_PATTERN; do
    val="$(eval "printf '%s' \"\${$v:-}\"")"
    grep -q "^$v=" "$MAIN/loop/stack.sh" 2>/dev/null && src="stack.sh" || src="defaut-loi"
    echo "[preflight]   $v='$val' ($src)"
  done
}
gate_selftest(){ # point 2: le gate s'execute sur l'arbre VERT avant le premier cycle.
  # S'il echoue ICI, c'est le HARNAIS qui est casse (commande malformee, toolchain
  # absente), jamais le code: REFUSE avec la commande et l'erreur, zero carte accusee.
  # (Les 9 faux REDCOMPILE du 08/07 seraient morts ici en 60 secondes.)
  local _mvnd _MVN _log
  _mvnd="$HOME/.sdkman/candidates/mvnd/current/bin/mvnd"                    # stack-default
  _MVN="${LOOP_MVN:-$([ -x "$_mvnd" ] && echo "$_mvnd" || echo ./mvnw)}"    # stack-default
  # meme formule de defauts que run-cycle.sh (garde par un test du harnais)
  GATE_FRONT_CMD="${GATE_FRONT_CMD:-npx ng build}"                          # stack-default
  GATE_BACK_CMD="${GATE_BACK_CMD:-$_MVN -q test-compile}"                   # stack-default
  if [ -z "$GATE_BACK_CMD" ] || [ -z "$GATE_FRONT_CMD" ]; then
    echo "[preflight] REFUSE: commande de gate VIDE (classe BUG C, contrat casse)"; return 1
  fi
  if [ -d "$BACK_DIR" ]; then
    _log="/tmp/$(basename "$MAIN")-selftest-back.log"
    if ! timeout 420 bash -c "cd '$BACK_DIR' && $GATE_BACK_CMD" >"$_log" 2>&1; then
      echo "[preflight] REFUSE: harnais mal configure, le gate back ECHOUE sur l'arbre connu-bon"
      echo "[preflight]   commande: (cd $BACK_DIR && $GATE_BACK_CMD)"
      tail -8 "$_log" | sed 's/^/[preflight]   /'
      return 1
    fi
    echo "[preflight] gate back OK sur arbre vert"
  fi
  if [ -d "$FRONT_DIR" ] && [ "${ARCH_PROFILE:-web-fullstack}" != "api-only" ]; then
    _log="/tmp/$(basename "$MAIN")-selftest-front.log"
    if ! timeout 420 bash -c "cd '$FRONT_DIR' && $GATE_FRONT_CMD" >"$_log" 2>&1; then
      echo "[preflight] REFUSE: harnais mal configure, le gate front ECHOUE sur l'arbre connu-bon"
      echo "[preflight]   commande: (cd $FRONT_DIR && $GATE_FRONT_CMD)"
      tail -8 "$_log" | sed 's/^/[preflight]   /'
      return 1
    fi
    echo "[preflight] gate front OK sur arbre vert"
  fi
  return 0
}
sig_of_last_cycle(){ # v6.46 point 3: signature d'echec normalisee du dernier log de cycle
  local l; l="$(ls -t loop/logs/cycle-*.log 2>/dev/null | head -1)"
  [ -n "$l" ] || { echo ""; return 0; }
  tail -40 "$l" | grep -oE 'bash: -c: line [0-9]+: syntax error[^"]{0,40}|syntax error: unexpected end of file|package [a-zA-Z0-9.]+ does not exist|cannot find symbol|HTTP [0-9]{3}: model[^"]{0,40}|error TS[0-9]+|API call failed[^"]{0,40}|Unable to connect[^"]{0,30}|ConnectionRefused|Unable to connect[^"]{0,30}|ConnectionRefused|[Tt]ry again at [0-9]{1,2}:[0-9]{2} ?[APap]?[Mm]?|usage limit[^"]{0,30}|rate.?limit(ed)?[^"]{0,30}' \
    | head -1 | sed 's/line [0-9]*/line N/'
  return 0
}
autopsy(){ # v6.46 point 6: un run a 0 vert ecrit POURQUOI, personne ne refait l'autopsie
  local sigs top n
  sigs="$(for l in $(ls -t loop/logs/cycle-*.log 2>/dev/null | head -30); do
    tail -40 "$l" | grep -oE 'bash: -c: line [0-9]+: syntax error[^"]{0,40}|syntax error: unexpected end of file|package [a-zA-Z0-9.]+ does not exist|cannot find symbol|HTTP [0-9]{3}: model[^"]{0,40}|API call failed[^"]{0,40}|Unable to connect[^"]{0,30}|ConnectionRefused|Unable to connect[^"]{0,30}|ConnectionRefused|[Tt]ry again at [0-9]{1,2}:[0-9]{2} ?[APap]?[Mm]?|usage limit[^"]{0,30}|rate.?limit(ed)?[^"]{0,30}' | head -1 | sed 's/line [0-9]*/line N/'
  done | sort | uniq -c | sort -rn | head -1)"
  n="$(printf '%s' "$sigs" | awk '{print $1}')"; top="$(printf '%s' "$sigs" | sed 's/^ *[0-9]* //')"
  [ -n "$top" ] || { echo "cause probable: makers muets ou aucune signature d'erreur dans les logs (verifier routage modele / profil)"; return 0; }
  case "$top" in
    *"syntax error"*)          echo "cause probable: HARNAIS (commande de gate/probe malformee), signature x$n: $top" ;;
    *"does not exist"*|*"cannot find symbol"*) echo "cause probable: compile sans classpath ou dependance manquante (verifier gate self-test), signature x$n: $top" ;;
    *"ry again at"*|*"limit"*)  echo "cause probable: QUOTA maker epuise en run (la pause quota aurait du tirer, verifier), signature x$n: $top" ;;
    *"HTTP"*|*"API call failed"*) echo "cause probable: ROUTAGE MODELE casse (profil/quota), signature x$n: $top" ;;
    *)                         echo "cause probable: echecs homogenes, signature x$n: $top" ;;
  esac
  return 0
}
maker_ping(){ # v6.47 (BUG D pilote): sonde DIRECTE du maker courant, une fois, par
  # famille. Sert au preflight ET en run (fast-fail x2 => est-ce l'infra ou le code?).
  local mk pong=""
  mk="${LOOP_MAKER_KIND:-$(esc_family "${DEFAULT_MAKER:-}")}"
  case "$mk" in
    codex)  pong="$(timeout 90 codex exec --sandbox read-only --skip-git-repo-check 'Reply with exactly: PONG' 2>/dev/null)" ;;
    claude) pong="$(timeout 90 claude -p 'Reply with exactly: PONG' --output-format text 2>/dev/null)" ;;
    stub)   pong="PONG" ;;
    *)      # v6.49: le maker local passe par HERMES (profil + provider + routage), PAS un
            # curl direct du endpoint. Le 09/07, model_alive (curl :1234) disait PONG alors
            # que le vrai chemin maker (hermes -> provider moa) etait casse: preflight vert,
            # maker muet, run degrade. On sonde le CHEMIN REEL quand un profil est adopte.
            if [ -n "${LOOP_HERMES_HOME:-}" ]; then
              pong="$(HERMES_HOME="$LOOP_HERMES_HOME" LOOP_REPO_ROOT="$WT" timeout 120 hermes -m "${DEFAULT_MAKER:-$MLXM}" -t file -z 'Reply with exactly: PONG' --cli 2>/dev/null | tail -3)"
            else
              model_alive && pong="PONG"
            fi ;;
  esac
  printf '%s' "$pong" | grep -q "PONG"
}
quota_pause(){ # v6.47 REQ1 (pilote): traverser une fenetre de quota comme on traverse
  # la nuit. L'erreur codex donne l'heure exacte ('try again at 2:02 PM'): on la LIT et on
  # dort jusque-la par tranches de 600s (re-sonde a chaque reveil, reprise anticipee si le
  # maker revient, jamais au-dela de la deadline). Heure illisible: 30min. La file est
  # PRESERVEE: aucune carte accusee, aucun routage, retry naturel a la reprise.
  local lg rst now target slice
  lg="$(ls -t loop/logs/cycle-*.log 2>/dev/null | head -1)"
  rst="$(tail -60 "$lg" 2>/dev/null | grep -oiE 'try again at [0-9]{1,2}:[0-9]{2} ?(AM|PM)?' | tail -1 | sed -E 's/^[Tt]ry again at //' | tr 'apm' 'APM')"
  now="$(date +%s)"; target=$(( now + 1800 ))
  if [ -n "$rst" ]; then
    local t
    t="$(date -j -f '%I:%M %p' "$rst" +%s 2>/dev/null || date -j -f '%H:%M' "$rst" +%s 2>/dev/null || echo "")"
    [ -n "$t" ] && [ "$t" -le "$now" ] && t=$(( t + 86400 ))
    [ -n "$t" ] && target=$(( t + 120 ))
  fi
  [ "$target" -gt $(( deadline - 700 )) ] && target=$(( deadline - 700 ))
  echo "[loop] QUOTA-PAUSE: maker muet, pause jusqu'a $(date -r "$target" '+%H:%M' 2>/dev/null || echo '?') (reset lu: ${rst:-aucun})"
  echo "- QUOTA-PAUSE: maker muet, pause jusqu'a $(date -r "$target" '+%H:%M' 2>/dev/null || echo '?') (reset lu: ${rst:-aucun})" >> "$REPORT"
  # v6.49.1: Telegram dedoublonne (1x/heure). quota_pause peut etre rappele a chaque carte
  # pendant un long incident fournisseur: une alerte par episode, pas une par entree.
  _now_q=$(date +%s)
  if [ $(( _now_q - ${quota_last_notify:-0} )) -gt 3600 ]; then
    notify_phone "⏳ Quota/maker muet ($(basename "$MAIN")): pause jusqu'a $(date -r "$target" '+%H:%M' 2>/dev/null || echo '?') (reset lu: ${rst:-aucun}). File preservee, reprise auto, aucune carte accusee. 1 alerte/heure."
    quota_last_notify=$_now_q
  fi
  while [ "$(date +%s)" -lt "$target" ] && [ $(( deadline - $(date +%s) )) -gt 700 ]; do
    slice=$(( target - $(date +%s) )); [ "$slice" -gt 600 ] && slice=600; [ "$slice" -lt 1 ] && break
    sleep "$slice"
    maker_ping && { echo "[loop] QUOTA-PAUSE: maker revenu avant l'heure, reprise"; return 0; }
  done
  return 0
}
quota_gate(){ # v6.52 QUOTA-GATE PROACTIF (proprietaire pilote: le run 2h a brule
  # jusqu'a 99% de codex sans jamais se mettre en pause; quota_pause v6.47 ne reagit
  # qu'au maker MUET, apres l'echec. Sa formule: "after each card there should be some
  # kind of eval: is the remaining quota enough for another cycle"). AVANT chaque cycle:
  # lire l'usage de la famille du MAKER (2 lectures locales, zero LLM), estimer le cout
  # d'un cycle (EMA des 5 derniers deltas: le loop apprend son propre cout), et si le
  # restant < max(1.5x cout, plancher 5%), PAUSE PROACTIVE par tranches de 10min jusqu'au
  # retour de marge (borne deadline). RESERVE DE FERMETURE: chair/critic/distill tournent
  # sur claude; si claude depasse 92%, on ne lance plus de cycle maker (il faut pouvoir
  # JUGER et FERMER le run). Telegram dedoublonne 1x/heure.
  local mk fam used="" cf="loop/state/quota-cost.tsv" prev ema=0 delta need rem cused=""
  mk="${LOOP_MAKER_KIND:-$(esc_family "${DEFAULT_MAKER:-}")}"
  case "$mk" in
    codex)  used="$(timeout 15 bash -c "${USAGE_CODEX_CMD:-true}" 2>/dev/null | grep -oE '[0-9]+([.][0-9]+)?' | tail -1)" ;;
    claude) used="$(timeout 15 bash -c "${USAGE_CLAUDE_CMD:-true}" 2>/dev/null | grep -oE '[0-9]+([.][0-9]+)?' | tail -1)" ;;
    *) return 0 ;;   # maker local: pas de quota
  esac
  [ -n "$used" ] || return 0   # capteur muet = on ne bloque jamais sur une absence de mesure
  used="${used%%.*}"
  # cout par cycle: EMA(5) des deltas entre lectures consecutives
  prev="$(tail -1 "$cf" 2>/dev/null | awk '{print $2}')"; ema="$(tail -1 "$cf" 2>/dev/null | awk '{print $3}')"
  if [ -n "$prev" ] && [ "$used" -ge "$prev" ] 2>/dev/null; then
    delta=$(( used - prev )); ema=$(( ( ${ema:-2} * 4 + delta ) / 5 )); [ "$ema" -lt 1 ] && ema=1
  else ema="${ema:-2}"; fi
  printf '%s	%s	%s
' "$(date +%s)" "$used" "$ema" >> "$cf"
  need=$(( ema * 3 / 2 )); [ "$need" -lt 5 ] && need=5
  rem=$(( 100 - used ))
  # reserve de fermeture (les organes de fermeture sont claude chez nous)
  if [ "$mk" != "claude" ] && { [ "${LOOP_LOT_CHAIR:-codex}" = claude ] || [ -n "${LOOP_CRITIC_MODEL:-}" ]; }; then
    cused="$(timeout 15 bash -c "${USAGE_CLAUDE_CMD:-true}" 2>/dev/null | grep -oE '[0-9]+' | tail -1)"
  fi
  if [ "$rem" -lt "$need" ] || { [ -n "$cused" ] && [ "$cused" -gt 92 ] 2>/dev/null; }; then
    echo "[loop] QUOTA-GATE: maker $mk a ${used}% (reste ${rem}%, besoin ~${need}%${cused:+, claude fermeture ${cused}%}): pause PROACTIVE avant le cycle"
    echo "- QUOTA-GATE proactif: pause a ${used}% ($mk), cout/cycle estime ${ema}%" >> "$REPORT"
    _now_g=$(date +%s)
    if [ $(( _now_g - ${quota_last_notify:-0} )) -gt 3600 ]; then
      notify_phone "$(printf '\xe2\x8f\xb3') Quota-gate proactif ($(basename "$MAIN")): $mk a ${used}%, pause AVANT d'entamer un cycle (cout estime ${ema}%/cycle). Reprise auto au retour de marge."
      quota_last_notify=$_now_g
    fi
    # v6.78 (nuit pilote 17-18/07 PERDUE: "toujours 83%, nouvelle pause 10min" en boucle
    # 2h20 puis run tue. Codex a supprime la fenetre 5h au profit d'un quota HEBDOMADAIRE:
    # la sonde lisait un champ dont la semantique a change sous nos pieds, valeur FIGEE, et
    # la boucle ne sortait que sur "marge revenue" qui n'arrivait jamais). Deux garde-fous:
    #   1. NON-PROGRESSION: une mesure identique 2 relectures d'affilee = metrique morte OU
    #      quota non-rechargeable (hebdo). Dans les DEUX cas attendre est inutile: on sort et
    #      on laisse tourner. Si le quota est vraiment epuise, l'appel modele echouera pour de
    #      vrai et quota_pause (reactif, qui lit l'heure de reset DU FOURNISSEUR) fera foi.
    #   2. PLAFOND: la pause proactive ne peut JAMAIS depasser _QG_MAX_SLICES tranches.
    # Doctrine: un gate PROACTIF pose sur une estimation n'a pas le droit de retenir une nuit
    # en otage. Seule une erreur REELLE du fournisseur justifie une longue attente.
    local _qg_same=0 _qg_prev="$used" _qg_slices=0 _QG_MAX_SLICES="${LOOP_QUOTA_MAX_SLICES:-3}"
    while [ $(( deadline - $(date +%s) )) -gt 1500 ]; do
      if [ "$_qg_slices" -ge "$_QG_MAX_SLICES" ]; then
        echo "[loop] QUOTA-GATE: plafond de pause proactive atteint ($(( _QG_MAX_SLICES * 10 ))min), on REPREND (le gate proactif ne retient pas la nuit; une vraie penurie sera vue par quota_pause)"
        echo "- QUOTA-GATE: plafond de pause atteint, reprise (mesure ${used}%)" >> "$REPORT"
        return 0
      fi
      sleep 600
      _qg_slices=$(( _qg_slices + 1 ))
      case "$mk" in
        codex)  used="$(timeout 15 bash -c "${USAGE_CODEX_CMD:-true}" 2>/dev/null | grep -oE '[0-9]+([.][0-9]+)?' | tail -1)" ;;
        claude) used="$(timeout 15 bash -c "${USAGE_CLAUDE_CMD:-true}" 2>/dev/null | grep -oE '[0-9]+([.][0-9]+)?' | tail -1)" ;;
      esac
      used="${used%%.*}"; rem=$(( 100 - ${used:-100} ))
      [ "$rem" -ge "$need" ] && { echo "[loop] QUOTA-GATE: marge revenue (${rem}%), reprise"; return 0; }
      if [ "$used" = "$_qg_prev" ]; then
        _qg_same=$(( _qg_same + 1 ))
        if [ "$_qg_same" -ge 2 ]; then
          echo "[loop] QUOTA-GATE: mesure FIGEE a ${used}% sur $(( _qg_same + 1 )) lectures = metrique morte ou quota non-rechargeable (hebdo): attendre ne sert a rien, on REPREND"
          echo "- QUOTA-GATE: mesure figee ${used}%, sonde jugee non fiable, reprise" >> "$REPORT"
          return 0
        fi
      else _qg_same=0; fi
      _qg_prev="$used"
      echo "[loop] QUOTA-GATE: toujours ${used}%, nouvelle pause 10min (tranche $_qg_slices/$_QG_MAX_SLICES)"
    done
    echo "[loop] QUOTA-GATE: deadline proche, on laisse la fermeture se faire"
  fi
  return 0
}
preflight(){ # point 5: la chaine entiere prouvee avant de depenser quota et deadline
  print_contract
  gate_selftest || return 1
  if [ "${LOOP_PREFLIGHT_SKIP_LLM:-0}" != 1 ]; then
    maker_ping || { echo "[preflight] REFUSE: maker (${LOOP_MAKER_KIND:-local}) muet au ping"; return 1; }
    echo "[preflight] maker repond"
    carto_llm 90 "Reply with exactly: PONG" | grep -q "PONG" || { echo "[preflight] REFUSE: cerveau des cartes muet (les deux familles)"; return 1; }
    echo "[preflight] cerveau des cartes repond"
  fi
  local _u
  for _u in "${USAGE_CLAUDE_CMD:-}" "${USAGE_CODEX_CMD:-}"; do
    [ -n "$_u" ] && echo "[preflight] quota: $(timeout 15 bash -c "$_u" 2>/dev/null | head -1 || true)"
  done
  echo "[preflight] CHAINE COMPLETE OK"
  return 0
}

# v6.2.8: F-cards have no probes, so AUTODONE cannot skip an already-green one; dedup
# them against FULL dev history (a carried F2 re-ran after its green merged, 2026-07-05)
for q in loop/state/queue/00-F*.md loop/state/queue/zz-E-*.md; do
  [ -f "$q" ] || continue
  n="$(basename "$q" .md)"; b="$(base_name "${n#00-F?-}")"
  { git log --format=%s "$BASE" 2>/dev/null | grep -q "^feat: $n \[loop"; } || \
  { git log --format=%s "$BASE" 2>/dev/null | grep -q "^feat: $b \[loop"; } && \
    { rm -f "$q"; echo "[loop] dropped already-green carried card $n"; }
done
if [ "$RESUMED" = "1" ]; then
  DONE_LOG="$(git log --format=%s "$BASE"..HEAD)"
  for q in loop/state/queue/*.md; do
    n="$(basename "$q" .md)"
    printf '%s\n' "$DONE_LOG" | grep -q "^feat: $n \[loop" && rm -f "$q"
  done
  echo "[loop] resume queue: $(ls loop/state/queue | wc -l | tr -d ' ') cards after skipping greens"
fi
touch loop/state/journal.md
JOURNAL="loop/state/journal.md"
# v6.50.4: RUN/REPORT deja poses tot (avant le semis). Ici on ne fait que le chrono de run.
: "${RUN:=$(date +%Y%m%d-%H%M%S)}"; : "${REPORT:=loop/reports/report-$RUN.md}"
STOP="loop/STOP"; rm -f "$STOP"
RUN_T0=$(date +%s)

# --- Phase 0 (v5.6 manifest-first, review OV-9): review a compact manifest of the
# WHOLE queue (name + GOAL/FILES/SCOPE/DEPENDS), so no card is invisible to a size cap.
phase0_review(){ # $1=label  reads card files from stdin list in $2 (glob)
  [ "${LOOP_PHASE0:-1}" = "1" ] && [ "${LOOP_CHECKER:-codex}" != "off" ] || return 0
  local label="$1" glob="$2" manifest out
  ls $glob >/dev/null 2>&1 || return 0
  manifest="$(for f in $(ls $glob | sort); do
    echo "### $(basename "$f" .md)"
    grep -E '^(GOAL|FILES|FILE|SCOPE|DEPENDS):|listed exactly|create exactly' "$f" | head -10
    echo
  done | head -c 20000)"
  out="$(carto_llm 300 "Review this manifest of task cards an autonomous coding loop will run in order. Flag ONLY real problems per card: OVERSIZED (>3 files or mixed concerns -> split), AMBIGUOUS spec, WRONG path, or depends-on-a-later-card. One terse line per flagged card: 'CARD <name>: <problem> - <fix>'. End with 'QUEUE: OK' or 'QUEUE: ISSUES'.

$([ -f loop/NIGHT-BRIEF.md ] && cat loop/NIGHT-BRIEF.md)

$manifest" 2>/dev/null)"
  printf '%s\n' "${out:-phase0 unavailable}" >> loop/state/queue-review.md
  local v; v="$(printf '%s' "$out" | grep -oE 'QUEUE: (OK|ISSUES)' | tail -1)"
  echo "[loop] phase0 ($label): ${v:-none}"
  printf -- '- [phase0 %s] %s\n' "$label" "${v:-none}" >> "$JOURNAL" 2>/dev/null || true
}
# v6.46: preflight AVANT phase0 (phase0 coute deja du LLM: rien ne se depense tant que
# la chaine n'est pas prouvee). REFUS = la fenetre est sauvee, pas brulee.
if ! preflight 2>&1; then
  notify_phone "⛔ PREFLIGHT REFUSE ($(basename "$MAIN")): harnais ou organe casse, run NON lance, aucune carte accusee. Cause exacte dans le driver log."
  echo "- PREFLIGHT REFUSE: run non lance (harnais/organe, voir driver log)" >> "$REPORT"
  exit 2
fi
if [ "${LOOP_DRYBOOT:-0}" = 1 ]; then
  echo "[loop] DRYBOOT: preflight OK, arret demande (aucun cycle, aucune depense)"
  exit 0
fi

: > loop/state/queue-review.md
phase0_review "initial" "loop/state/queue/*.md"

echo "[loop] queue: $(ls loop/state/queue | wc -l | tr -d ' ') cards   STOP file: $WT/$STOP"

caffeinate -i -w $$ & CAFF=$!
# pidfile (v5.7.2): robust loop detection despite the snapshot-exec renaming the
# process to /tmp/loop-driver-<pid>. afk-watch + health checks read this.
# v6.18: garde anti-doublon par worktree. Incident pilote: bascule maker=codex
# a lance un 2e driver sans arreter le 1er (Opus), deux drivers sur le meme worktree
# (course git + double consommation quota). RUNNING detenu par un pid VIVANT et
# DIFFERENT = refus (le resurrecteur relance apres mort, RUNNING pointe alors un pid
# mort, le garde passe). LOOP_FORCE=1 outrepasse (usage delibere seulement).
if [ -f "$MAIN/loop/RUNNING" ]; then
  _other="$(cat "$MAIN/loop/RUNNING" 2>/dev/null)"
  if [ -n "$_other" ] && [ "$_other" != "$$" ] && kill -0 "$_other" 2>/dev/null && [ "${LOOP_FORCE:-0}" != "1" ]; then
    echo "[loop] REFUSE: un driver tourne deja sur ce worktree (pid $_other). LOOP_FORCE=1 pour outrepasser."; exit 2
  fi
fi
# v6.49.3 REAPER D'ORPHELINS (spirale OOM de la nuit du 09/07: 8 drivers, plusieurs
# run-cycle concurrents). Un driver tue par l'OOM-killer meurt en SIGKILL: son trap
# cleanup NE S'EXECUTE PAS, donc son run-cycle enfant survit, reparente a launchd, et
# continue son ng build. Le resurrecteur relance alors un driver qui demarre un NOUVEAU
# cycle -> DEUX builds concurrents sur la meme machine -> OOM -> mort -> orphelin ->
# spirale. SIGKILL contourne les traps, donc le remede doit etre au DEMARRAGE de
# l'incarnation suivante: invariant UN SEUL cycle par worktree. On tue tout run-cycle.sh
# dont le cwd est CE worktree et qui n'est pas nous. Portee CDC pure (cwd verifie), les
# autres loops (pilote/agrigrement) intacts.
for _rc in $(pgrep -f 'loop/run-cycle.sh' 2>/dev/null); do
  [ "$_rc" = "$$" ] && continue
  _rcw="$(lsof -a -p "$_rc" -d cwd -Fn 2>/dev/null | grep '^n' | head -1 | cut -c2-)"
  case "$_rcw" in
    "$WT"*|"$MAIN"*)
      echo "[loop] reaper: run-cycle orphelin $_rc (cwd $_rcw), on tue son arbre (invariant 1 cycle)"
      for _k in $(pgrep -P "$_rc" 2>/dev/null) "$_rc"; do kill "$_k" 2>/dev/null; done ;;
  esac
done
# v6.39.2: persister l'env de lancement pour le RESURRECTEUR (sinon il relance sans
# LOOP_MLX -> run ollama avec des tags ESCALATED mlx -> 404; vu a la resurrection 05:52).
# v6.57: NIGHT-ENV COMPLET (le routing par role v6.50 n'y etait pas: une resurrection
# aurait perdu carto/critic/chair/front-review et l'effort) + NIGHT-PLAN (deadline epoch)
# pour le RESURRECTEUR AU BOOT (2 reboots machine sans trace en 2 jours, chacun pendant un
# run actif: celui du 12/07 09:00 a coute 4h de fenetre; un LaunchAgent lit NIGHT-PLAN au
# demarrage et relance le reliquat, cf loop/boot-resurrect.sh).
{ printf 'export LOOP_MLX=%s LOOP_NO_LOCAL_LLM=%s LOOP_MAKER_KIND=%s LOOP_MAKER=%s LOOP_CLAUDE_EFFORT=%s\n' \
    "${LOOP_MLX:-0}" "${LOOP_NO_LOCAL_LLM:-0}" "${LOOP_MAKER_KIND:-hermes}" "${LOOP_MAKER:-}" "${LOOP_CLAUDE_EFFORT:-medium}"
  printf 'export LOOP_ESCALATION_MAKER=%s LOOP_CARTO_MODEL=%s LOOP_CRITIC_MODEL=%s LOOP_FRONT_REVIEW_MODEL=%s LOOP_LOT_CHAIR=%s\n' \
    "${LOOP_ESCALATION_MAKER:-}" "${LOOP_CARTO_MODEL:-}" "${LOOP_CRITIC_MODEL:-}" "${LOOP_FRONT_REVIEW_MODEL:-}" "${LOOP_LOT_CHAIR:-codex}"
} > "$MAIN/loop/NIGHT-ENV"
echo "$deadline" > "$MAIN/loop/NIGHT-PLAN"
echo $$ > "$MAIN/loop/RUNNING"
cleanup(){ echo "[loop] stopping"; kill "$CAFF" 2>/dev/null
  # v6.68: reap au depart (traps definis plus bas; sortie avant leur definition = no-op)
  type reap_browsers >/dev/null 2>&1 && reap_browsers
  type reap_worktree_orphans >/dev/null 2>&1 && reap_worktree_orphans
  ollama stop "$DEFAULT_MAKER" 2>/dev/null; ollama stop "$ESCALATION_MAKER" 2>/dev/null
  # v6.20: liberer le modele MLX (charge a TTL 24h) quand AUCUNE relance n'est planifiee
  # (STOP humain, ou NIGHT-PLAN absent). Si le resurrecteur doit relancer (NIGHT-PLAN
  # present, pas de STOP), on GARDE le modele charge pour un redemarrage a chaud.
  if [ -f "$MAIN/loop/STOP" ] || [ ! -f "$MAIN/loop/NIGHT-PLAN" ]; then
    command -v lms >/dev/null 2>&1 && lms unload --all >/dev/null 2>&1 && echo "[loop] MLX decharge (pas de relance planifiee)"
  fi
  rm -rf "$WT/tmp"; rm -f "$MAIN/loop/RUNNING"; }
trap cleanup EXIT

green_c=0; red_c=0; skip_c=0; hard_c=0; blocked_c=0; consec=0; cyc=0; last_green_cyc=0; sterile_notified=0
{ echo "# Overnight card-driven build $RUN (harness v5.6)"; echo
  echo "Worktree: $WT   Base: $BASE   Deadline: $(date -r "$deadline")"
  echo "Checker: codex BLOCKING (fail-closed)   Escalation: $ESCALATION_MAKER"; echo; echo "## Cards"; } > "$REPORT"

# v6.6: la boite aux lettres existe toujours, et l'inbox du matin est consommee AVANT la file
[ -f loop/FEEDBACK.md ] || { printf '%s\n' "$FEEDBACK_HDR" > loop/FEEDBACK.md; git add loop/FEEDBACK.md >/dev/null 2>&1; }
consume_feedback
printf '\n=== RUN %s (v5.6, base %s, deadline %s) ===\n' "$RUN" "$BASE" "$(date -r "$deadline")" >> "$JOURNAL"

# ============================ v6.0 LOT REVIEW =================================
# Per-card codex review is replaced (LOOP_REVIEW=lot, default) by ONE review per LOT.
# The per-card DETERMINISTIC gate (compile+tests+smoke+probes) is unchanged law: every
# card still only commits gate-green. Codex then judges the lot's CUMULATIVE diff, where
# it can see integration truth (does the form speak the API's real contract), instead of
# per-card slices where cross-card findings were ~half noise and convergence loops burned
# 20-60min per block.
# LOTS ARE DERIVED BY THE LOOP ITSELF, deterministically: a card's cluster is the ROOT of
# its DEPENDS chain (05,13,20 -> lot "05"). A lot closes on cluster change, LOOP_LOT_SIZE
# greens, or queue end.
# ON LOT FAIL (user law): NOTHING is reverted, the lot's code already passed the gate and
# is working software. The findings become a NEW FIX-LOT card (00-F<gen>-, sorts first)
# that rides the exact same machinery: maker -> gate -> commit -> reviewed with its own
# lot. Fix generations cap at 2; residual findings go to proposals for the morning review.
# v6.2.1: queue prefixes never stack (zz-D-zz-E-zz-D-x churned the name machinery).
LOT_FILE="loop/state/lot.tsv"; LOT_BASE=""; LOT_CLUSTER=""
cluster_of(){ # $1=card name -> root of its DEPENDS chain (max 5 hops, cycle-safe)
  local n="$1" dep i=0
  while [ "$i" -lt 5 ]; do
    dep="$(grep -m1 '^DEPENDS:' "loop/tasks/$n.md" 2>/dev/null | awk '{print $2}')"
    if [ -z "$dep" ] || [ ! -f "loop/tasks/$dep.md" ]; then break; fi
    n="$dep"; i=$(( i + 1 ))
  done
  echo "$n"
}
lot_open(){ [ -s "$LOT_FILE" ]; }
# v6.2 PIPELINING: lot_review no longer blocks the loop. lot_close snapshots the lot
# state, clears the globals (the next lot opens immediately), and runs the review in the
# BACKGROUND while the next card's maker generates. Safe because: the reviewer is
# READ-ONLY (the gate already compiled/tested everything, no build needed), its only
# writes are its log, the REPORT line, the ledger and possibly ONE fix-card file in the
# queue. Consecutive reviews serialize on a lock dir. GPU never idles waiting for review.
LOT_LOCK="loop/state/.lot-review.lock"
lot_close(){ # snapshot + background review; returns immediately
  lot_open || return 0
  local SNAP_ID="${LOT_CLUSTER:-lot}" SNAP_BASE="$LOT_BASE" SNAP_CARDS SNAP_N
  SNAP_CARDS="$(awk '{print $1}' "$LOT_FILE" | tr '\n' ' ')"
  SNAP_N="$(wc -l < "$LOT_FILE" | tr -d ' ')"
  : > "$LOT_FILE"; LOT_BASE=""; LOT_CLUSTER=""
  ( lot_review_exec "$SNAP_ID" "$SNAP_BASE" "$SNAP_CARDS" "$SNAP_N" ) &
  echo "[lot] review of '$SNAP_ID' ($SNAP_N cards) running in background (pid $!)"
}
lot_wait(){ # run-end barrier: let in-flight reviews finish (cap 15min)
  local w=0
  while [ -d "$LOT_LOCK" ] && [ "$w" -lt 900 ]; do sleep 5; w=$(( w + 5 )); done
  sleep 1
}
lot_review_exec(){ # $1=lotid $2=base $3=cards $4=n  (background-safe, arg-based)
  local LOTID="$1" LBASE="$2" CARDS="$3" N="$4"
  local GEN DIFFSTAT DIFF RVP OUT V FINDINGS CARDTEXTS c FIX w=0
  # serialize concurrent reviews
  while ! mkdir "$LOT_LOCK" 2>/dev/null; do sleep 5; w=$(( w + 5 )); [ "$w" -ge 900 ] && return 0; done
  trap 'rmdir "$LOT_LOCK" 2>/dev/null' RETURN
  echo "[lot] reviewing lot '$LOTID' ($N cards: $CARDS)"
  DIFFSTAT="$(git diff --stat "$LBASE"..HEAD 2>/dev/null | tail -20)"
  DIFF="$(git diff "$LBASE"..HEAD 2>/dev/null | head -c 60000)"
  # v6.52 TRIAGE MECANIQUE (economie de revue, design proprietaire pilote: Opus par
  # lot meme pour du CSS de 5 lignes = le vrai gouffre; le gate garantit deja build+
  # probes+smoke). Un lot BON-MARCHE = petit diff, mono-couche, ZERO token de contrat
  # (endpoint/DTO/entity/route). Ces criteres sont greppables et CONSERVATEURS: au
  # moindre doute (un seul critere rate), le lot est A-RISQUE et paie le chair complet.
  if [ "${LOOP_TRIAGE:-1}" = 1 ]; then
    _CHG="$(git diff --shortstat "$LBASE"..HEAD 2>/dev/null | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | awk '{s+=$1} END{print s+0}')"
    _TOUCH_B=0; _TOUCH_F=0
    [ -n "$BACK_DIR" ] && git diff --name-only "$LBASE"..HEAD 2>/dev/null | grep -q "^$BACK_DIR/" && _TOUCH_B=1
    [ -n "$FRONT_DIR" ] && git diff --name-only "$LBASE"..HEAD 2>/dev/null | grep -q "^$FRONT_DIR/" && _TOUCH_F=1
    _CONTRACT=0
    printf '%s' "$DIFF" | grep -qE '@(Get|Post|Put|Delete|Patch|Request)Mapping|record [A-Z][A-Za-z]*Dto|@Entity|export const routes|path: ' && _CONTRACT=1
    if [ "${_CHG:-999}" -le "${LOOP_TRIAGE_MAXLINES:-120}" ] && [ $(( _TOUCH_B + _TOUCH_F )) -le 1 ] && [ "$_CONTRACT" = 0 ]; then
      echo "[lot] TRIAGE: lot '$LOTID' BON-MARCHE (${_CHG:-?} lignes, mono-couche, zero contrat): gate seul, pas de chair"
      printf '%s	%s	PASS	triage-cheap
' "$(date '+%F %H:%M')" "$LOTID" >> loop/reports/scores.tsv 2>/dev/null
      printf -- '- [lot] %s PASS (triage bon-marche, gate seul)
' "$LOTID" >> "$JOURNAL" 2>/dev/null
      return 0
    fi
    echo "[lot] TRIAGE: lot '$LOTID' A-RISQUE (lignes=${_CHG:-?} couches=$(( _TOUCH_B + _TOUCH_F )) contrat=$_CONTRACT): chair complet"
  fi
  CARDTEXTS=""
  for c in $CARDS; do
    CARDTEXTS="$CARDTEXTS
### $c
$(sed -n '1,12p' "loop/tasks/$c.md" 2>/dev/null)"
  done
  RVP="You are a pragmatic senior engineer reviewing a LOT of $N related changes an AI
teammate shipped (each already compiles, passes tests and a runtime smoke; they are
COMMITTED working software). Judge the lot AS AN INTEGRATED WHOLE: do the pieces speak
each other's real contracts, is the behaviour sound end to end, is anything existing
broken. Do NOT re-litigate style or file choices. Findings must be REAL defects or
integration mismatches, each on one line starting '- [<file>] ' with a concrete fix.
Do not run builds (the harness did). End with exactly 'VERDICT: PASS' or 'VERDICT: FAIL'.

## THE LOT'S CARDS
$CARDTEXTS

## CUMULATIVE DIFF (stat)
$DIFFSTAT

## CUMULATIVE DIFF
$DIFF"
  # v6.25: relecteur de lot diversifiable (angle mort codex-juge-codex signale par pilote:
  # sous un maker codex, un relecteur codex trouve a repetition des findings sur sa propre
  # sortie et churn les fix-lots). LOOP_LOT_CHAIR=claude relit avec l'autre famille.
  OUT=""  # v6.50 (attrape par release-smoke, 5e recidive def-avant-usage, version variable:
          # OUT n'existait que dans la branche chair=claude; chair codex => set -u crash 1032)
  if [ "${LOOP_LOT_CHAIR:-codex}" = "claude" ] && command -v claude >/dev/null 2>&1; then
    OUT="$(timeout 420 claude -p "$RVP" --output-format text 2>/dev/null)"
    [ -n "$OUT" ] && echo "[lot] chair: claude (diversifie)"
  fi
  [ -n "$OUT" ] || OUT="$(timeout 420 codex exec --sandbox read-only --skip-git-repo-check "$RVP" 2>/dev/null)"
  printf '%s\n' "$OUT" > "loop/logs/lot-review-$LOTID-$(date +%H%M%S).log"
  V="$(printf '%s' "$OUT" | grep -oiE 'VERDICT: *(PASS|FAIL)' | tail -1 | grep -oiE 'PASS|FAIL' | tr '[:lower:]' '[:upper:]')"
  FINDINGS="$(printf '%s' "$OUT" | grep -E '^[[:space:]]*- \[' | head -c 6000)"
  if [ "$V" = "PASS" ] || [ -z "$V" ]; then
    echo "[lot] $LOTID review: ${V:-no-verdict, accepted} (gate already guaranteed working code)"
    echo "- LOT $LOTID ($N cards): review ${V:-none}" >> "$REPORT"
  else
    # v6.28 (finding 17 pilote): compteur de generations PERSISTANT par feature-base,
    # pas derive des prefixes F du lot courant (qui se reinitialise au changement de
    # cluster -> churn: depot-dossier vert 5x avant que le conseil n'attrape, 40 min
    # brules). Cap dur LOOP_LOT_MAXGEN (defaut 2): au-dela -> conseil direct, pas N
    # re-reviews de plus. Le conseil reste la soupape, mais borne, pas apres le churn.
    # v6.80 (run 27/07: carte '00-F1-00-F1-45-ged-recherche-client-fixes-fixes' observee en
    # supervision. Le nom reutilisait LOTID ENTIER, donc chaque generation empilait un
    # prefixe 00-F<gen>- et un suffixe -fixes. Consequence en chaine: au tour suivant le
    # strip ci-dessous (UN prefixe, UN suffixe) rendait une base DIFFERENTE, donc un
    # compteur NEUF, donc MAXGEN jamais atteint => churn de fix-lots non borne. Aggravant:
    # le compteur vit sous loop/state (gitignore, DANS le worktree recree a chaque run),
    # donc il etait de toute facon perdu d'un run a l'autre.
    # Fix: 1) base NORMALISEE (strip repete) et nom bati sur LOT_BASE, stable de generation
    # en generation; 2) compteur persiste dans le MAIN, hors worktree, pour que le cap
    # tienne a travers les runs.
    LOT_BASE="$LOTID"
    while :; do
      # v6.82: stripper TOUS les prefixes de reparation, pas seulement 00-F. Le run du
      # 27/07 a produit '00-F1-00-E2E-reparer-...-fixes': la carte 00-E2E n'etait pas
      # reconnue comme base, donc le nom s'allongeait encore et la base derivait, meme
      # maladie que v6.80 sur une autre porte. Les motifs listes ici sont exactement ceux
      # que v6.81 traite comme cartes de reparation (00-F*, 00-E2E*, zz-E-*).
      _lb="$(printf '%s' "$LOT_BASE" | sed 's/^00-F[0-9]*-//; s/^00-E2E-//; s/^zz-E-//; s/-fixes$//')"
      [ "$_lb" = "$LOT_BASE" ] && break
      LOT_BASE="$_lb"
    done
    LOT_BASE="$(printf '%s' "$LOT_BASE" | tr -cd 'a-zA-Z0-9-')"
    mkdir -p "$MAIN/loop/lot-gen"
    CF="$MAIN/loop/lot-gen/$LOT_BASE.count"     # persistant: survit au reset du worktree
    GEN=$(( $(cat "$CF" 2>/dev/null || echo 0) + 1 )); echo "$GEN" > "$CF"
    MAXGEN="${LOOP_LOT_MAXGEN:-2}"
    if [ "$GEN" -le "$MAXGEN" ]; then
      FIX="loop/state/queue/00-F$GEN-$LOT_BASE-fixes.md"
      { echo "# Fix lot $LOTID, reviewer findings (generation $GEN)"
        echo
        echo "USE CASE:"
        echo "A reviewer inspected the last $N shipped changes as a whole ($CARDS) and found"
        echo "the integration defects below. Make them right: the features must work together"
        echo "end to end. All of that code is committed and working, refine it, do not rebuild."
        echo
        echo "FINDINGS (verbatim, fix EVERY one):"
        printf '%s\n' "$FINDINGS"
        echo
        echo "DONE WHEN:"
        echo "- Every finding above is addressed; the app still builds and all tests pass."
        echo "SCOPE: full"
        # v6.72 (matin 17/07: 9 fix-lots sans VALUE jamais pioches, l'e2e est reste rouge
        # tout un run pendant que des P0 features passaient devant): une regression
        # constatee prime sur une feature neuve, le fix-lot nait P0.
        echo "VALUE: P0"
      } > "$FIX"
      mkdir -p "$MAIN/loop/wip/queue-carry"; cp "$FIX" "$MAIN/loop/wip/queue-carry/" 2>/dev/null
      echo "[lot] $LOTID review: FAIL ($(printf '%s\n' "$FINDINGS" | grep -c .) findings) -> fix-lot queued ($(basename "$FIX")), NOTHING reverted"
      echo "- LOT $LOTID: FAIL -> fix-lot gen $GEN queued (code kept, fix-forward)" >> "$REPORT"
    elif [ "$GEN" -eq $(( MAXGEN + 1 )) ]; then
      # v6.1: runtime fixing exhausted => the question is APPROACH, convene the COUNCIL.
      # It rules (3 lenses + web evidence), writes loop/DECISIONS.md, and may queue ONE
      # final council-directed 00-F3 card. PREFERENCE-class rulings proceed on the
      # completeness-preserving default, marked OVERTURNABLE for the morning review.
      mkdir -p "loop/proposals/$(date +%Y%m%d)"
      printf '%s\n' "$FINDINGS" > "loop/proposals/$(date +%Y%m%d)/lot-$LOTID-residual-findings.txt"
      bash loop/council.sh "$LOTID" "loop/proposals/$(date +%Y%m%d)/lot-$LOTID-residual-findings.txt" 2>&1 | sed 's/^/[loop] /'
      echo "- LOT $LOTID: COUNCIL convened after $MAXGEN fix-gens (see loop/DECISIONS.md)" >> "$REPORT"
      rm -f "$CF" 2>/dev/null  # le conseil a tranche, le compteur repart (sa directive est un neuf)
      notify_phone "🏛️ Council ruled on lot $LOTID, decision in loop/DECISIONS.md (overturnable at morning review)"
    else
      # beyond the council's one directive: ledger + morning, hard stop (no infinite ladder)
      mkdir -p "loop/proposals/$(date +%Y%m%d)"
      printf '%s\n' "$FINDINGS" > "loop/proposals/$(date +%Y%m%d)/lot-$LOTID-residual-findings.txt"
      echo "[lot] $LOTID: council directive also failed review, residuals to the morning (final)"
      echo "- LOT $LOTID: post-council residuals to proposals (FINAL)" >> "$REPORT"
    fi
  fi
}

# v5.9.1/.4: bank the failed attempt BEFORE reverting, code AND the reason it failed.
# "Maybe it's a single line out of 10000 that made it fail; restarting from scratch makes
# no sense." The diff + the rejection findings are saved to MAIN (survives worktree
# recycling); the retry session gets both, applies the patch, and fixes the exact lines.
bank_wip(){ # $1=commit-name  $2=failure-kind (RED|REDCOMPILE|FAIL|...)
  mkdir -p "$MAIN/loop/wip"
  git add -A >/dev/null 2>&1
  git diff --cached HEAD 2>/dev/null | head -c 200000 > "$MAIN/loop/wip/$1.patch"
  [ -s "$MAIN/loop/wip/$1.patch" ] || rm -f "$MAIN/loop/wip/$1.patch"
  # v6.2.7 toxicity guard: a bank carrying mass deletions re-deletes those files on every
  # "apply your previous attempt" retry (card 25 poisoned itself this way). Quarantine it.
  if [ -f "$MAIN/loop/wip/$1.patch" ] && [ "$(grep -c '^deleted file' "$MAIN/loop/wip/$1.patch")" -gt 5 ]; then
    NDEL="$(grep -c '^deleted file' "$MAIN/loop/wip/$1.patch")"
    mv "$MAIN/loop/wip/$1.patch" "$MAIN/loop/wip/$1.patch.TOXIC"
    # the retry must KNOW why there is no patch, and what not to repeat
    { echo "## CRITICAL WARNING FROM YOUR PREVIOUS ATTEMPT"
      echo "It DELETED $NDEL existing files (its patch was quarantined, so there is nothing"
      echo "to apply, deliberately). Build this card ADDITIVELY from the clean tree: create"
      echo "new files next to the existing code, never delete/move/rewrite existing files,"
      echo "never recreate a module directory inside itself."
      echo
      cat "$MAIN/loop/wip/$1.findings.txt" 2>/dev/null
    } > "$MAIN/loop/wip/$1.findings.tmp" && mv "$MAIN/loop/wip/$1.findings.tmp" "$MAIN/loop/wip/$1.findings.txt"
    echo "[loop] bank for $1 QUARANTINED ($NDEL deletions), retry warned to build additively"
  fi
  # the WHY must match the failure KIND. A gate-RED banking a stale checker block from a
  # previous run told the retry the WRONG story (2026-07-05).
  local CLOG WHY="" KIND="${2:-}"
  CLOG="$(ls -t loop/logs/cycle-*-"$1".log 2>/dev/null | head -1)"
  case "$KIND" in
    RED*)
      # SIGNAL over boilerplate: a Spring stacktrace drowned the root cause once
      # (5KB of context-customizer dumps, zero Caused-by lines survived the cap).
      # causes FIRST (they must never fall off the cap) and EVERY line hard-truncated:
      # three 2KB Spring context-dump lines once ate the whole 5KB budget by themselves.
      WHY="## GATE FAILURE (build/tests/smoke), the SIGNAL lines
### root causes (Caused by + OUR code frames)
$(grep -E 'Caused by|at com\.app|APPLICATION FAILED' /tmp/$PSLUG_D-verify-svc.log /tmp/$PSLUG_D-verify-boot.log 2>/dev/null | cut -c1-220 | sort -u | head -15)
### failing tests (one line each, truncated)
$(grep -E '^\[ERROR\] +[A-Za-z].*(Test|IT)\.' /tmp/$PSLUG_D-verify-svc.log 2>/dev/null | cut -c1-200 | sort -u | head -8)
### front build tail
$(tail -8 /tmp/$PSLUG_D-verify-front.log 2>/dev/null | cut -c1-200)"
      # durable evidence: /tmp logs are overwritten by the next cycle; keep this card's
      # full gate output where the autopsy can always find it
      cp /tmp/$PSLUG_D-verify-svc.log "loop/logs/verify-$1-$(date +%H%M%S).log" 2>/dev/null
      cp /tmp/$PSLUG_D-verify-boot.log "loop/logs/verifyboot-$1-$(date +%H%M%S).log" 2>/dev/null ;;
    *)
      if [ -n "$CLOG" ]; then
        WHY="$(awk '/^########## CHECKER \(codex/{b=""; f=1} f{b=b $0 ORS} END{printf "%s", b}' "$CLOG" 2>/dev/null | head -c 4000)"
        [ -n "$WHY" ] || WHY="$(awk '/^########## COMPILE-REPAIR/{b=""; f=1} f{b=b $0 ORS} END{printf "%s", b}' "$CLOG" 2>/dev/null | head -c 4000)"
      fi ;;
  esac
  [ -n "$WHY" ] && printf '%s\n' "$WHY" | head -c 5000 > "$MAIN/loop/wip/$1.findings.txt" || rm -f "$MAIN/loop/wip/$1.findings.txt"
  [ -f "$MAIN/loop/wip/$1.patch" ] && echo "[loop] banked failed attempt: loop/wip/$1.patch ($(wc -c < "$MAIN/loop/wip/$1.patch" | tr -d ' ') bytes) + findings ($KIND)"
}

# ============================ v6.4 LE CARTOGRAPHE =============================
# Le deck initial etait humain; le fini-du-deck n'est PAS le fini-de-l-app. Quand la
# file se vide et qu'il reste du temps, le cartographe compare le CAHIER (domain-rules,
# roadmap, NIGHT-BRIEF humain s'il existe, night-review du loop) au CODE REEL et emet
# de NOUVELLES cartes use-case. La file se nourrit du north star, plus du deck.
# Garde: un seul refill par run, 4 cartes max, les mauvaises cartes meurent au gate et
# le distilleur les reecrit, comme toutes les autres.
CARTO_DONE=0
build_coverage(){ # v6.47 REQ4+BUG F (pilote: couverture-opinion 0/20 sur un repo aux
  # features fonctionnelles => cartes doublons => conflits de compile). La liste des
  # features DEJA LIVREES est un FAIT git, pas une impression LLM: elle est calculee et
  # imposee au carto. Les yeux EYE_* restent la verite du code, ceci est la verite du LIVRE.
  { echo "### Cartes deja VERTES (git log, features livrees: NE PAS re-emettre)"
    git log --format=%s 2>/dev/null | grep -E '^feat: [a-zA-Z0-9_-]+ \[loop' \
      | sed -E 's/^feat: //; s/ \[loop.*//' | sort -u | head -80 | sed 's/^/- /'
  } > loop/state/coverage-mech.md
}
cartographer(){
  # v6.46: desactivable (LOOP_CARTO=0) pour les runs de smoke/consommation pure: le
  # release-smoke execute un cycle reel sur projet jouet SANS depenser un appel LLM.
  [ "${LOOP_CARTO:-1}" = 1 ] || { echo "[carto] desactive (LOOP_CARTO=0)"; return 1; }
  [ "$CARTO_DONE" = 1 ] && return 1
  [ $(( deadline - $(date +%s) )) -gt 2700 ] || return 1
  # v6.23: d'abord, decouper les cartes PARKEES (trop grosses, echec repete). Le loop le
  # fait seul: codex decompose en sous-cartes executables au lieu d'attendre un humain.
  local parked psub
  for parked in loop/state/parked/*.md; do
    [ -f "$parked" ] || continue
    grep -q '^SPLIT-REQUEST:' "$parked" 2>/dev/null || continue
    local pname; pname="$(basename "$parked" .md)"
    echo "[carto] decoupage auto de la carte parkee $pname..."
    psub="$(carto_llm 300 "Cette carte de tache a echoue les makers car TROP GROSSE. Decoupe-la en 2 ou 3 sous-cartes INDEPENDANTES et plus petites, chacune un seul objectif nommable, chacune avec USE CASE / DONE WHEN (<=2) / SCOPE / PROBE executable. Enchaine-les par DEPENDS si besoin. REGLE PROBES (cartes front): un PROBE ne doit JAMAIS exiger un test unitaire ecrit par le maker (npm test / ng test / spec TestBed): prouver par build vert + rg du cablage (+ e2e si dispo). PROBES EN ET: un rg par token chaine par && (jamais une alternance rg multi-features, c'est un OU qui ment), au moins un token SPECIFIQUE a la sous-carte. Chaque sous-carte porte 'VALUE: P1|P2|P3' (P1 = debloquant demo, P2 defaut, P3 confort): herite de la valeur de la carte mere sauf si une sous-carte est clairement du confort. Emets UNIQUEMENT des blocs:
===NEW-CARD <slug-kebab>===
<contenu de la sous-carte>
===END===

LA CARTE TROP GROSSE:
$(cat "$parked")" 2>/dev/null)"
    if printf '%s' "$psub" | grep -q '===NEW-CARD '; then
      printf '%s\n' "$psub" | awk '/^===NEW-CARD /{p=$0; sub(/^===NEW-CARD /,"",p); sub(/===$/,"",p); gsub(/[^a-zA-Z0-9-]/,"",p); f="loop/state/queue/50-" p ".md"; inb=1; n++; if(n>3){inb=0}; next} /^===END===$/{if(inb){close(f)}; inb=0; next} inb{print >> f}'
      for nc in loop/state/queue/50-*.md; do [ -f "$nc" ] && cp "$nc" "loop/tasks/$(basename "$nc")" 2>/dev/null; done
      git rm -q "$parked" 2>/dev/null || rm -f "$parked"
      git add loop/tasks loop/state/queue 2>/dev/null; git commit -q -m "carto: decoupe $pname en sous-cartes [loop]" 2>/dev/null
      echo "[carto] $pname decoupee en sous-cartes"
      echo "- CARTO: carte trop grosse $pname decoupee automatiquement" >> "$REPORT"
      CARTO_DONE=1; return 0
    fi
  done
  CARTO_DONE=1
  echo "[carto] file vide, analyse d'ecart cahier vs code..."
  local TREE APIS BRIEF NR CP OUT N
  # v6.43: extensions contractuelles (EYE_SRC_EXTS), plus de *.ts/*.java en dur: sur
  # flutter/php/.net les yeux scannaient ZERO fichier et le carto etait aveugle.
  TREE="$(for _e in ${EYE_SRC_EXTS:-ts java}; do find "$EYE_FRONT_SRC" "$EYE_ENTITY_DIR" -name "*.$_e" 2>/dev/null; done | sed 's|.*/||' | sort -u | head -80 | tr '\n' ' ')"
  APIS="$(grep -rhoE '@(Get|Post|Put|Delete)Mapping\([^)]*\)' "$EYE_ENTITY_DIR" 2>/dev/null | sort -u | head -30)"
  # v6.4.1 les YEUX MECANIQUES: preuves calculees, pas des impressions
  # cablage: ce que le front APPELLE vraiment vs ce que le back EXPOSE
  FRONT_CALLS="$(grep -rhoE "'[^']*api[^']*'" "$EYE_FRONT_SRC" --include='*.ts' 2>/dev/null | sort -u | head -15)"
  # interactivite: combien de boutons cliquables par ecran (une app sans clicks est morte)
  CLICKS="$(find "$EYE_FRONT_SRC" -name '*.html' -exec grep -l "$EYE_CLICK_PATTERN" {} + 2>/dev/null | sed 's|.*src/app/||')"
  CLICKS_N="$(find "$EYE_FRONT_SRC" -name '*.html' -exec grep -o "$EYE_CLICK_PATTERN" {} + 2>/dev/null | wc -l | tr -d ' ')"
  # ecrans encore sur donnees statiques au lieu du back
  STATIC="$(grep -rl "$EYE_STATIC_PATTERN" "$EYE_FRONT_SRC" --include='*.ts' 2>/dev/null | sed 's|.*src/app/||')"
  # maquette vs construit
  MAQ="$(ls "$EYE_MAQ_DIR/" 2>/dev/null)"
  PAGES="$(ls "$EYE_PAGES_DIR/" 2>/dev/null)"
  # seed: entites vs couverture du seeder
  ENTS="$(grep -rl "$EYE_ENTITY_PATTERN" "$EYE_ENTITY_DIR" 2>/dev/null | sed 's|.*/||;s|\.[A-Za-z]*$||' | tr '\n' ' ')"
  SEEDCOV="$(grep -oE 'new [A-Z][A-Za-z]+|Repository\.save' "$EYE_SEEDER_FILE" 2>/dev/null | sort -u | head -15 | tr '\n' ' ')"
  # dette de realisme: ce qui est encore fake, stub ou mock
  FAKES="$( { find "$EYE_ENTITY_DIR" "$EYE_FRONT_SRC" \( -iname '*fake*' -o -iname '*stub*' -o -iname '*mock*' \) -not -path '*/node_modules/*' -not -path '*/vendor/*' -not -path '*/.dart_tool/*' 2>/dev/null; grep -rli 'fake' "$EYE_ENTITY_DIR" --include="*.${EYE_ENTITY_EXT:-java}" 2>/dev/null; } | sort -u | sed 's|.*src/||' | head -8 | tr '\n' ' ')"
  E2E_N="$(ls $EYE_E2E_GLOB 2>/dev/null | wc -l | tr -d ' ')"
  # v6.17: capteur de fidelite maquette (oeil mecanique, alimente le cartographe)
  MAQFID="$(bash loop/maquette-fidelity.sh "$WT" 2>/dev/null | head -12)"
  # v6.24: socle front. Un "shell vide" (composants sans vrai template) fait echouer en
  # boucle les cartes de conformite (probes clic/POST). On compte les pages REELLES.
  REAL_PAGES="$(grep -rlE 'templateUrl|template *:' "$EYE_PAGES_DIR" --include='*.ts' 2>/dev/null | wc -l | tr -d ' ')"
  MAQ_SCREENS="$(ls "$EYE_MAQ_DIR"/*.html 2>/dev/null | wc -l | tr -d ' ')"
  PAGES_N="$(ls "$EYE_PAGES_DIR/" 2>/dev/null | wc -l | tr -d ' ')"
  BRIEF="$( { cat loop/NIGHT-BRIEF.md 2>/dev/null; ls -t loop/feedback/archive-*.md 2>/dev/null | head -2 | xargs cat 2>/dev/null; } | head -c 2500)"
  NR="$(cat docs/night-review.md 2>/dev/null | head -c 2500)"
  CP="Tu es le CARTOGRAPHE d'un loop autonome qui construit $PROJECT_DOMAIN.
La file de taches est VIDE mais l'application n'est PAS finie. Compare le cahier des
charges au code reel et emets les 4 prochaines cartes les plus utiles.

## LE CAHIER, regles metier
$(head -c 4000 docs/domain-rules.md 2>/dev/null)

## BRIEF HUMAIN, priorites du proprietaire, poids maximal si present
$BRIEF

## LA REVUE DU LOOP SUR L'APP
$NR

## LE CODE REEL, fichiers
$TREE

## LES ENDPOINTS REELS DU BACK
$APIS

## CE QUE LE FRONT APPELLE VRAIMENT, le cablage reel
$FRONT_CALLS
(tout endpoint du back absent de cette liste est une feature MORTE pour l'utilisateur)

## INTERACTIVITE REELLE, total de (click) dans l'app: $CLICKS_N
Ecrans avec au moins un click: $CLICKS
(un ecran de la maquette sans clicks est un ecran non cable)

## ECRANS ENCORE SUR DONNEES STATIQUES au lieu du back
$STATIC

## MAQUETTE, ecrans attendus
$MAQ
## ECRANS CONSTRUITS
$PAGES

## ENTITES vs SEEDER, la demo doit avoir des donnees partout
Entites: $ENTS
Le seeder cree: $SEEDCOV

## CE QUI EST ENCORE FAKE, la dette de realisme
$FAKES
(lentille REEL: un fake VERT dont la source reelle est nommee dans le cahier declenche
une carte analyse-contrat avec DEPENDS sur la chaine fake, puis une carte connecteur)

## TESTS RUNTIME (la verite du clic)
$E2E_N spec(s) Playwright pour $PAGES_N ecrans construits
(un ecran sans spec dedie n'a jamais ete clique par personne)

## FIDELITE MAQUETTE (structurel, boutons/champs/colonnes maquette vs page)
$MAQFID
$( [ "${MAQ_AUTHORITY:-direction}" = "structure" ] && \
  echo "(un ecart marque = page loin de sa maquette: emettre une carte de mise en conformite)" || \
  echo "(v6.50, decision proprietaire pilote 895c85a: la maquette est une DIRECTION, un
moodboard de niveau et d'ambiance, PAS un contrat structurel. Un ecart structurel n'est
PAS un defaut. Ce qui compte: COMPLETUDE DES CAS D'USAGE (l'ecran sert toutes les actions
de son cas d'usage du cahier, praticables) + respect des regles produit de l'annexe
docs/ameliorations.md. Emettre une carte seulement pour une action MANQUANTE ou une regle
violee, jamais pour 'coller aux blocs de la maquette'.)" )

## SOCLE FRONT (une carte de conformite front sans socle echoue en boucle)
Pages reelles construites (template non vide): $REAL_PAGES pour $MAQ_SCREENS ecrans maquette
(si le front est un shell quasi vide, SEQUENCE D'ABORD une carte de fondation, layout +
routing + service HTTP + une vraie page, puis fais DEPENDRE les cartes de conformite front
sur cette fondation. N'emets pas de carte de clic sur du vide.)

## LENTILLES DE DETECTION, applique chacune systematiquement
$(sed -e "s/{{FRONT_DIR}}/$FRONT_DIR/g" -e "s/{{BACK_DIR}}/$BACK_DIR/g" loop/carto-lenses.md 2>/dev/null)

## COUVERTURE MECANIQUE (verite git, calculee par le driver, PAS une opinion)
$(build_coverage; cat loop/state/coverage-mech.md 2>/dev/null)
INTERDIT (v6.47, tempete de doublons pilote): emettre une carte pour une feature de
la liste VERTE ci-dessus, sauf a citer dans le USE CASE un manque PRECIS et verifiable
(fichier absent, endpoint absent, page vide) que tes PROBEs testent. Chaque NEW-CARD
doit avoir des PROBEs qui ECHOUENT sur l'arbre ACTUEL: une carte qui nait deja
satisfaite est un doublon (le driver la droppe en AUTODONE, quota gaspille).

VALEUR PRODUIT (v6.47): chaque NEW-CARD porte une ligne 'VALUE: P1|P2|P3'. P1 = change
la DEMO produit (socle front, premier ecran cable, seed de demo, submit bout-en-bout).
P2 = defaut. P3 = confort, refactor, dette interne. La file s'execute par VALUE
croissante puis nom: un P3 ne passe JAMAIS devant un P1 en attente.

ORDRE API-AVANT-FRONT (v6.50, pilote: deux fois une carte front appelant un endpoint
a ete planifiee AVANT la carte back qui le cree -> 404 transitoire, cycle gaspille). Si
une carte d'ecran front que tu emets appelle un endpoint (/api/...) qu'une AUTRE carte de
ce meme lot construit cote back, la carte front DOIT porter 'DEPENDS: <nom-carte-back>'.
Le back se construit et se verifie avant le front qui le consomme. Tu connais les deux
cartes: cable la dependance toi-meme, ne compte pas sur le maker pour improviser l'endpoint.

REGISTRE STABLE DES CAS D'USAGE (v6.50, pilote: le denominateur de couverture errait
17/18/16/15 d'un run a l'autre car tu relisais le cahier a chaque fois, rendant le % de
progression inutilisable). Le fichier docs/use-cases.md est le REGISTRE FIXE: une ligne
par cas d'usage, id stable 'UC-NN', append-only (on peut AJOUTER un UC decouvert, jamais
renumeroter ni supprimer). S'il n'existe pas, ta matrice ci-dessous en tient lieu et sera
committee comme registre initial. Ta matrice de couverture DOIT utiliser ces ids comme
denominateur fixe: la progression devient monotone et rapportable (11/16, puis 12/16).
$( [ -f docs/use-cases.md ] && echo "Registre actuel:" && cat docs/use-cases.md | head -40 )

Emets AUSSI, avant les cartes, UN bloc de couverture (matrice use cases du cahier,
ids UC-NN du registre). REDEFINITION DE COUVERT (v6.51, retour proprietaire pilote:
'depot fonctionne' etait vert alors que le formulaire demandait un NNI a une societe):
COUVERT-VERT exige DEUX preuves: (1) la couverture mecanique ci-dessus (carte verte ou
fichier cite) ET (2) un spec e2e de PARCOURS d'experience pour cet UC (l'utilisateur
remplit, soumet, retrouve, ouvre, agit) present et vert. Un UC dont seul l'endpoint
repond = PARTIEL au mieux, avec en Preuve 'parcours manquant'. La couverture peut donc
BAISSER quand la barre monte: c'est la verite, pas une regression:
===COVERAGE===
| Use case du cahier | Etat | Preuve |
|---|---|---|
| <un par ligne> | COUVERT-VERT / EN-FILE / MANQUANT / PARTIEL | <carte ou fichier> |
===END===

REGLE ABSOLUE SI PAGES_N < 2: ta PREMIERE carte DOIT etre le socle front (routing racine,
client HTTP, une page reelle branchee au back). Toute carte d'ecran DEPEND du socle.
PROBES DU SOCLE, EN ET (remontee 20: le socle d'pilote a AUTODONE sur un rg-OU dont
un seul token generique existait deja): un rg PAR token, chaines par && ou en lignes
PROBE separees, avec au moins un token propre au socle CREE (sa route racine, sa page
d'accueil). Et elles prouvent le CABLAGE (build
front vert + presence des tokens routing/client HTTP dans les sources), JAMAIS la suite
de tests unitaires par defaut du squelette: remplacer le shell casse MECANIQUEMENT le
spec par defaut (app.spec & co) et le probe echoue meme quand le socle est correct. Et
le corps de la carte socle DOIT dire au maker de mettre a jour ou remplacer les specs
par defaut du squelette qu'il modifie.

PROBES DES CARTES D'ECRAN FRONT (le VRAI mur, diagnostic pilote du 08/07: 5 runs
cales dessus): le PROBE d'une carte d'ecran ne doit JAMAIS exiger un test unitaire
front ecrit par le maker (npm test, ng test, spec TestBed/HttpTestingController). Le
composant du maker est presque toujours bon; c'est le SPEC qui rate au premier jet
(providers, flush, matching des mocks), et le revert atomique jette un ecran correct a
90%. Un ecran se prouve par: (1) build front vert, (2) rg du cablage reel (endpoint
appele, route declaree, params), (3) si l'outillage e2e existe, un spec e2e minimal qui
charge l'ecran: le PROBE verifie l'EXISTENCE et le CONTENU du spec (test -f && rg des
etapes cles), JAMAIS son execution (executer la suite e2e est INTERDIT en PROBE: EPERM
dans le sandbox maker, timeout cote driver; l'execution appartient a la phase e2e du
harnais, qui a les ports et le temps). Les tests unitaires front vivent dans des cartes DEDIEES dont le corps
fournit un GABARIT de spec complet a REMPLIR (config TestBed + client HTTP de test +
exemple de flush qui passe): le maker rate l'invention de la config, pas le remplissage.

SEMANTIQUE DES PROBES rg: EN ET, JAMAIS EN OU (remontee 20 pilote, l'angle mort le
plus subtil: rg \"provideHttpClient|HttpClient|routerLink\" est un OU, UN seul token
generique deja present ailleurs suffit, la carte nait 'satisfaite' et AUTODONE la
droppe: le loop CROIT le front couvert alors que l'ecran n'existe pas). Regles dures:
(a) chaque token dans SON PROPRE rg, chaines par && (rg \"provideRouter\" src && rg
\"path: 'demandeur'\" src && ...), ou en lignes PROBE separees (chaque ligne doit
passer). (b) au moins UN token SPECIFIQUE a la feature de LA carte (sa route, son
endpoint, son selecteur), jamais uniquement des tokens generiques (HttpClient,
routerLink, Routes, provideRouter) qui existent des le premier composant du projet.
(c) une alternance rg n'est permise que pour des variantes du MEME token (ex:
\"getDossier|get_dossier\"), jamais pour couvrir plusieurs features.

CARTES PARKEES A DECOUPER (chacune a echoue en boucle, trop grosse; REMPLACE-la par 2-3
sous-cartes executables en un pass chacune, la premiere = le socle qui manquait):
$(ls loop/state/parked/*.md 2>/dev/null | head -3 | while read pf; do echo "--- $(basename "$pf")"; head -20 "$pf"; done)

PRIORITES ABSOLUES dans cet ordre: 1 cabler le front au back (chaque ecran lit et ecrit
via l'API reelle, zero donnees statiques), 2 conformite a la maquette ecran par ecran,
3 seed complet pour une demo credible de bout en bout, 4 seulement ensuite du neuf.

Emets EXACTEMENT des blocs de ce format, 4 maximum, les plus forte valeur d'abord.
Une carte = UN objectif nommable par un utilisateur, format use-case strict:
===NEW-CARD <slug-kebab>===
# Carte, <titre court>
USE CASE:
<qui fait quoi, voit quoi, 4-8 lignes>
CONTEXT:
<ou regarder, conventions, 2-4 lignes>
DONE WHEN:
- <critere 1>
- <critere 2 max 3>
SCOPE: front|back|full
PROBE: <un test executable ou grep par critere>
===END==="
  OUT="$(carto_llm 420 "$CP")"
  [ -n "$OUT" ] || { echo "[carto] codex indisponible"; return 1; }
  printf '%s\n' "$OUT" > "loop/logs/cartographer-$(date +%H%M%S).log"
  N=0
  printf '%s\n' "$OUT" | awk '/^===NEW-CARD /{p=$0; sub(/^===NEW-CARD /,"",p); sub(/===$/,"",p); gsub(/[^a-zA-Z0-9-]/,"",p); f="loop/state/queue/50-" p ".md"; inb=1; n++; if(n>4){inb=0}; next} /^===END===$/{if(inb){close(f)}; inb=0; next} inb{print >> f}'
  for q in loop/state/queue/50-*.md; do
    [ -f "$q" ] || continue
    N=$(( N + 1 ))
    cp "$q" "loop/tasks/$(basename "$q")" 2>/dev/null
  done
  # v6.43.1: 3e site (le trou vu chez pilote): les cartes du REFILL carto atterrissent
  # ici sans passer par les semis, donc sans cablage DAG. Si le carto a ecrit un socle,
  # les cartes front doivent etre suspendues DERRIERE lui (pas par chance alphabetique).
  sanitize_cards
  ensure_front_scaffold 2>/dev/null
  printf '%s\n' "$OUT" | awk '/^===COVERAGE===$/{f=1;next} /^===END===$/{f=0} f' > /tmp/$(basename "$MAIN")-carto-cov.md
  if [ -s /tmp/$(basename "$MAIN")-carto-cov.md ]; then
    { echo "# Couverture use cases, generee par le cartographe, $(date '+%F %H:%M')"; echo
      cat /tmp/$(basename "$MAIN")-carto-cov.md; } > docs/coverage.md
    COV_T="$(( $(grep -c '^|' docs/coverage.md) - 2 ))"; [ "$COV_T" -lt 0 ] && COV_T=0; COV_V="$(grep -c 'COUVERT-VERT' docs/coverage.md)"
    echo "[carto] couverture: $COV_V/$COV_T use cases verts"
    echo "- COUVERTURE: $COV_V/$COV_T use cases verts (docs/coverage.md)" >> "$REPORT"
    git add docs/coverage.md 2>/dev/null
    # v6.50: REGISTRE STABLE. Premiere matrice emise = registre initial fige (ids UC-NN,
    # append-only): le denominateur ne peut plus errer d'un run a l'autre.
    if [ ! -f docs/use-cases.md ]; then
      { echo "# Registre des cas d'usage (FIXE, append-only, ids stables UC-NN)"
        echo "# Ajouter un UC decouvert est permis; renumeroter ou supprimer est interdit."
        grep '^|' docs/coverage.md | awk -F'|' 'NR>2{n++; printf "- UC-%02d:%s\n", n, $2}'
      } > docs/use-cases.md
      git add docs/use-cases.md 2>/dev/null
      echo "[carto] registre use-cases initialise ($(grep -c '^- UC-' docs/use-cases.md) UC)"
    fi
  fi
  if [ "$N" -gt 0 ]; then
    git add loop/tasks/50-*.md 2>/dev/null
    git commit -q -m "carto: $N nouvelles cartes depuis l'ecart cahier vs code [loop]" 2>/dev/null
    echo "[carto] $N nouvelles cartes en file"
    echo "- CARTOGRAPHE: $N nouvelles cartes generees (ecart cahier vs code)" >> "$REPORT"
    notify_phone "🗺️ Cartographe: file vide, $N nouvelles cartes generees depuis le cahier"
    return 0
  fi
  return 1
}

# failure routing + escalation ladder. Tier is ESCALATED: marker or zz-E- prefix.
# Fast-defer (v5.7.11): a first block does NOT retry inline; the escalation retry is
# prefixed zz-E- so it sorts to the TAIL (after fresh cards, before zz-H-), letting the
# achievable cards bank first instead of one tar-pit card eating the whole run.
# (review OV-10: MAKER: is a manual PREFERENCE that keeps the ladder; ESCALATED: is the tier).
route_failure(){ # $1=CARD $2=NAME $3=reason
  mkdir -p loop/state/failed loop/state/cooldown   # v6.47: jamais un mv silencieusement rate
  local escalated=0
  { [[ "$2" == zz-E-* ]] || grep -q '^ESCALATED:' "$1" 2>/dev/null; } && escalated=1
  if [ "$escalated" = "1" ]; then
    local ORIG; ORIG="$(base_name "$2")"
    local CLOG; CLOG="$(ls -t loop/logs/cycle-*-"$2".log loop/logs/cycle-*-"$ORIG".log 2>/dev/null | head -1)"
    if [ -n "$CLOG" ] && [ -f "loop/tasks/$ORIG.md" ]; then
      { echo; echo "## LESSONS, tentative rejetée du $(date +%Y-%m-%d) ($3)"
        echo "Findings du reviewer (corrige-les par construction au prochain essai):"
        sed -n '/CHECKER (codex/,$p' "$CLOG" | grep -vE "^\[|tokens used|session id|^-+$|^user$|^codex$" | tail -c 1800
      } >> "loop/tasks/$ORIG.md"
      # v5.7.2 SPLIT-ME: both local makers exhausted => the SPEC is likely too big.
      # Human reframes/splits at the milestone (free judgment, NOT a paid frontier).
      grep -q '^SPLIT-ME:' "loop/tasks/$ORIG.md" 2>/dev/null || \
        printf '\nSPLIT-ME: failed both local makers %s — human: split or simplify this card\n' "$(date +%F)" >> "loop/tasks/$ORIG.md"
      git add "loop/tasks/$ORIG.md" && git commit -q -m "lessons+split-me: $ORIG [loop]" 2>/dev/null
    fi
    if grep -q '^SPLIT-ME:' "loop/tasks/$ORIG.md" 2>/dev/null && grep -q '^## LESSONS' "loop/tasks/$ORIG.md" 2>/dev/null; then
      # v6.23: carte trop grosse qui re-echoue APRES un SPLIT-ME => PARK (hors file ET
      # hors tasks: plus de re-seed, plus de brulage quota en boucle). Marquee pour
      # decoupage automatique par le cartographe (SPLIT-REQUEST).
      mkdir -p loop/state/parked
      grep -q '^SPLIT-REQUEST:' "loop/tasks/$ORIG.md" 2>/dev/null || \
        printf '\nSPLIT-REQUEST: parked %s apres echec repete, le cartographe doit decouper\n' "$(date +%F)" >> "loop/tasks/$ORIG.md"
      git add "loop/tasks/$ORIG.md" 2>/dev/null; git commit -q -m "park+split-request: $ORIG [loop]" 2>/dev/null
      git mv "loop/tasks/$ORIG.md" "loop/state/parked/$ORIG.md" 2>/dev/null || mv "loop/tasks/$ORIG.md" "loop/state/parked/$ORIG.md" 2>/dev/null
      rm -f "$1" 2>/dev/null
      echo "- $2: PARKED (echec repete apres split-me), attend decoupage cartographe" >> "$REPORT"
      printf -- '- [driver] %s PARKED for auto-split (%s)\n' "$2" "$3" >> "$JOURNAL"
      notify_phone "📦 Carte $ORIG parkee (trop grosse, echec repete): le cartographe la decoupera. Plus de brulage quota dessus."
    else
      mv "$1" loop/state/failed/ 2>/dev/null
      echo "- $2: FAILED after escalation ($3), lessons appended" >> "$REPORT"
      printf -- '- [driver] %s FAILED after escalation (%s)\n' "$2" "$3" >> "$JOURNAL"
    fi
  else
    mv "$1" "loop/state/queue/zz-E-$(base_name "$2").md" 2>/dev/null
    # v6.47 BUG E (pilote, tempete de retries 16:58): un requeue immediat = marteau
    # sur la meme carte. Cooldown 15min, le selecteur la saute tant qu'il court.
    echo "$(( $(date +%s) + 900 ))" > "loop/state/cooldown/zz-E-$(base_name "$2").md.cd"
    # v6.2.11: escalation retries survive run boundaries too (a council directive's zz-E
    # died with the fork on 2026-07-05; only lot fix-cards were carried until now)
    mkdir -p "$MAIN/loop/wip/queue-carry"
    cp "loop/state/queue/zz-E-$(base_name "$2").md" "$MAIN/loop/wip/queue-carry/" 2>/dev/null
    if [ -f "loop/tasks/$2.md" ] && ! grep -q '^ESCALATED:' "loop/tasks/$2.md"; then
      printf '\nESCALATED: %s\n' "$ESCALATION_MAKER" >> "loop/tasks/$2.md"
      git add "loop/tasks/$2.md" && git commit -q -m "escalate: $2 -> $ESCALATION_MAKER [loop]" 2>/dev/null
    fi
    echo "- $2: $3, escalating to $ESCALATION_MAKER" >> "$REPORT"
    printf -- '- [driver] %s %s, escalated\n' "$2" "$3" >> "$JOURNAL"
  fi
  # v6.47 ceinture (tempete 24x pilote, cycles 4 a 28 sur la MEME carte): quel que
  # soit le chemin ci-dessus, la carte qui vient d'echouer DOIT avoir quitte sa place
  # en file. Un mv silencieusement rate = boucle infinie. Quarantaine forcee sinon.
  if [ -f "$1" ]; then
    echo "[loop] ROUTAGE RATE: $2 encore en file apres routage, quarantaine forcee"
    printf -- '- [driver] %s ROUTAGE RATE, quarantaine forcee\n' "$2" >> "$JOURNAL"
    mv "$1" "loop/state/failed/$(basename "$1")" 2>/dev/null || rm -f "$1"
  fi
}

pick_card(){ # v6.47 REQ3+E (pilote: le socle demo a attendu 3 runs derriere du churn
  # backend alphabetique). La file s'execute par VALEUR PRODUIT: VALUE: P0..P3 (defaut
  # P2) puis nom (les prefixes zz-D/E/H restent en queue de leur palier). Les cartes en
  # cooldown (echec recent) sont sautees tant que l'horloge court.
  local f v now cd
  now="$(date +%s)"
  for f in loop/state/queue/*.md; do
    [ -f "$f" ] || continue
    cd="loop/state/cooldown/$(basename "$f").cd"
    if [ -f "$cd" ]; then
      [ "$(cat "$cd" 2>/dev/null || echo 0)" -gt "$now" ] && continue
      rm -f "$cd"
    fi
    v="$(grep -m1 -oE '^VALUE: *P[0-3]' "$f" 2>/dev/null | grep -oE 'P[0-3]')"
    printf '%s %s\n' "${v:-P2}" "$f"
  done | sort | head -1 | cut -d' ' -f2-
}

# v6.59: REAPER NAVIGATEUR + REASSERTION GPU-OFF. 3 reboots machine sans trace
# (11/12/13-07), chacun a ~1-2 min d'un chromium headless: crash renderer GPU (Metal)
# -> WindowServer tombe -> reset dur sans panic. Deux gardes, en TETE de chaque cycle,
# donc AVANT que la carte suivante ne lance quoi que ce soit:
#   1. tuer tout chromium/headless_shell survivant (le maker lance playwright HORS du
#      trap de e2e.sh: rien ne garantissait le reap; un zombie GPU wedge la machine).
#   2. reimposer les flags GPU-off dans playwright.config.ts (le maker peut le reecrire
#      pendant sa carte; on le reasserte, il ne peut jamais relancer un chromium GPU nu).
reap_browsers(){
  pkill -f 'headless_shell' 2>/dev/null
  pkill -f 'Chromium.*--headless' 2>/dev/null
  pkill -f 'chrome.*--headless' 2>/dev/null
  pkill -f 'playwright.*chromium' 2>/dev/null
  # v6.60.2: le webServer playwright (ng serve 4317, reuseExistingServer) survivait a la
  # fin du run (395Mo orphelins constates 3 fois). Port dedie e2e, aucun dev ne l'utilise.
  pkill -f 'ng serve --port 4317' 2>/dev/null
  true
}
# v6.68 (constat proprietaire 16/07: java/node orphelins apres les runs; le reaper ne
# connaissait que chromium + ng serve, les boots Spring et esbuild echappaient aux traps
# quand le driver sortait). GENERALISATION: tout process dont la COMMANDE reference le
# chemin du worktree appartient au loop par definition (personne d'autre n'execute depuis
# $WT), donc reapable quel que soit son type (java spring-boot, node, esbuild, futur
# outil). Jamais de faux positif: le filtre est le chemin, pas le nom du binaire. Les
# sessions maker/checker (claude/codex CLI) sont EXEMPTEES: cwd worktree mais gerees par
# run-cycle (les tuer ici avorterait le cycle en cours).
reap_worktree_orphans(){
  [ -n "${WT:-}" ] || return 0
  local p cmd
  for p in $(pgrep -f -- "$WT" 2>/dev/null); do
    [ "$p" = "$$" ] && continue
    cmd="$(ps -o command= -p "$p" 2>/dev/null)"
    case "$cmd" in
      *loop-overnight*|*run-cycle*|*claude*|*codex*|*hermes*) continue ;;  # organes vivants du run
      *"$WT"*) kill -9 "$p" 2>/dev/null && echo "[loop] reap orphelin worktree: pid $p (${cmd:0:80})" ;;
    esac
  done
  true
}
assert_pw_gpu_off(){
  local cfg="frontend/playwright.config.ts"
  [ -f "$cfg" ] || return 0
  # si les flags GPU manquent (config neuve du maker), on les reinjecte dans use{}
  grep -q 'use-gl=swiftshader' "$cfg" 2>/dev/null && return 0
  if grep -q 'launchOptions' "$cfg" 2>/dev/null; then
    echo "[loop] WARN: playwright.config a un launchOptions SANS swiftshader, reassertion GPU-off requise (verifier $cfg)"
    return 0
  fi
  # inject apres 'headless: true,' (ancre stable). Gardes ci-dessus deja verifiees:
  # ni swiftshader ni launchOptions presents, la substitution est donc sure.
  perl -0pi -e 's/(headless:\s*true,)/$1\n    launchOptions: { args: ["--disable-gpu","--disable-software-rasterizer","--disable-gpu-compositing","--disable-accelerated-2d-canvas","--in-process-gpu","--use-gl=swiftshader","--no-sandbox"] },/' "$cfg" 2>/dev/null \
    && echo "[loop] playwright.config: flags GPU-off reinjectes (le maker les avait retires)"
}

# v6.62: SIDECAR (sidecar, 2e repo du perimetre). Reset en TETE de cycle = ardoise
# propre pour le maker et atomicite (tout revert RED du CDC est couvert: le sidecar sale
# d'un cycle rouge est remis a plat ici avant la carte suivante). Gardes DURES: SIDECAR_DIR
# non vide, repo git, et DISTINCT du worktree courant (jamais reset le CDC par erreur).
sidecar_reset(){
  [ -n "${SIDECAR_DIR:-}" ] || return 0
  [ -d "$SIDECAR_DIR/.git" ] || return 0
  case "$(cd "$SIDECAR_DIR" && pwd -P)" in "$(pwd -P)"|"$WT"|"$MAIN") return 0 ;; esac
  git -C "$SIDECAR_DIR" reset --hard HEAD >/dev/null 2>&1
  git -C "$SIDECAR_DIR" clean -fd >/dev/null 2>&1
}
# v6.62.1: le sidecar a-t-il des changements non commites? Sert au no-change guard et au
# FALSE-GREEN guard, tous deux CDC-only avant: une carte sidecar-only ne bougeait pas le
# worktree CDC -> "no change" -> travail du maker JETE au reset du cycle suivant (bug du
# 1er run multi-repo, 15/07). Desormais un sidecar sale compte comme un vrai changement.
sidecar_dirty(){
  [ -n "${SIDECAR_DIR:-}" ] && [ -d "$SIDECAR_DIR/.git" ] || return 1
  [ -n "$(git -C "$SIDECAR_DIR" status --porcelain 2>/dev/null | head -1)" ]
}
# v6.64 AUTODONE-LATE (3 cartes decision-* du 15/07: features LIVREES par des cartes
# soeurs, probes bruts passants, mais motif 'rg X && rg Y' neutralise par le lint =>
# jamais AUTODONE au semis => rejeu no-change en boucle jusqu'au park, 2-3 cycles brules
# par carte, traites a la main pendant le run 8h). La loi absorbe la classe: sur un
# no-change, on execute les probes BRUTS de la carte (y compris ceux que runnable_probes
# neutralise, formats 'PROBE: cmd' ET liste '- `cmd`'). TOUS passent (>=1 probe, rc=0
# partout) => la carte est FAITE, on la classe, on ne la rejoue pas. Un probe malforme
# (rc>=2) echoue naturellement => pas d'autodone abusif, la carte suit l'escalier normal.
raw_probes_all_pass(){ # $1 = fichier carte; rc 0 = au moins 1 probe et tous passent
  local card="$1" n=0 cmd
  while IFS= read -r cmd; do
    [ -z "$cmd" ] && continue
    n=$(( n + 1 ))
    ( timeout 60 bash -c "$cmd" ) >/dev/null 2>&1 || return 1
  done < <(
    { grep -E '^PROBE: ' "$card" 2>/dev/null | sed 's/^PROBE: //'
      sed -n '/^PROBE[[:space:]]*$/,/^[A-Z][A-Z-]*:*[[:space:]]*$/p' "$card" 2>/dev/null \
        | grep -E '^- `' | sed 's/^- `//; s/`$//'
    } | sed 's/[[:space:]]*$//' )
  [ "$n" -ge 1 ]
}
# commit du sidecar COUPLE au GREEN du CDC (meme nom de carte). Rien a committer = no-op.
sidecar_commit(){ # $1 = nom carte, $2 = sha CDC
  [ -n "${SIDECAR_DIR:-}" ] && [ -d "$SIDECAR_DIR/.git" ] || return 0
  [ -n "$(git -C "$SIDECAR_DIR" status --porcelain 2>/dev/null | head -1)" ] || return 0
  git -C "$SIDECAR_DIR" add -A >/dev/null 2>&1
  git -C "$SIDECAR_DIR" commit -q -m "feat: $1 [loop, couple CDC $2]" >/dev/null 2>&1 \
    && echo "[loop] sidecar committe ($SIDECAR_DIR) couple au vert CDC $2"
}

while :; do
  reap_browsers            # v6.59: aucun chromium ne survit dans la carte suivante
  reap_worktree_orphans    # v6.68: aucun java/node/esbuild du worktree ne survit non plus
  assert_pw_gpu_off        # v6.59: GPU toujours coupe, meme si le maker a reecrit la config
  sidecar_reset            # v6.62: ardoise propre du sidecar (couvre tout revert RED precedent)
  # v6.2.7: state self-heal. Something (most plausibly a maker terminal rm) deleted
  # loop/state mid-run on 2026-07-05, orphaning the queue and journal. The driver now
  # recreates its own organs every cycle and says so loudly instead of limping.
  if [ ! -d loop/state/queue ]; then
    echo "[loop] WARNING: loop/state vanished mid-run, self-healing (queue is LOST, rebuilding from tasks minus greens)"
    mkdir -p loop/state/queue loop/state/done loop/state/failed
    cp loop/tasks/*.md loop/state/queue/
# v6.38 FIX A (nuit 2026-07-08): dedup UNIVERSELLE au semis. Une carte deja verte dans
# l'historique ET sans PROBE (fix-lot residuelle type 91-fix-critical, verte 4x) ne peut
# ni etre AUTODONE (pas de probe) ni etre dedup'ee par v6.2.8 (motifs 00-F*/zz-E* seuls).
# Elle empoisonne chaque run: maker no-change -> faux positif infra -> boucle de pause.
for q in loop/state/queue/*.md; do
  [ -f "$q" ] || continue
  qn="$(basename "$q" .md)"
  if ! grep -q '^PROBE' "$q" 2>/dev/null && git log --format=%s "$BASE" 2>/dev/null | grep -q "^feat: $(base_name "$qn") \[loop"; then
    rm -f "$q"; echo "[loop] seed-dedup: $qn deja vert et sans probe, retire de la file"
    continue
  fi
  # v6.83 (regression de v6.81, vue au run post-merge du 27/07): la dedup ci-dessus ne
  # traite QUE les cartes sans probe, parce qu'AVANT v6.81 une carte de reparation deja
  # faite sortait de la file par AUTODONE. v6.81 a ferme cette porte (a raison: des probes
  # verts sur une reparation sont des probes suspects) mais sans ouvrir l'autre: ces cartes
  # ne sortaient plus JAMAIS seules et revenaient a chaque run bruler un cycle pour finir
  # en no-change. Ici la preuve n'est pas la probe, c'est l'HISTORIQUE: un commit
  # 'feat: <carte> [loop' signifie que le gate a valide ce travail et qu'il est dans la base.
  case "$(base_name "$qn")" in
    00-F*|00-E2E*|zz-E-*)
      if git log --format=%s "$BASE" 2>/dev/null | grep -q "^feat: $(base_name "$qn") \[loop"; then
        rm -f "$q"; echo "[loop] seed-dedup: $qn (reparation) deja verte dans l'historique de $BASE, retiree de la file"
      fi ;;
  esac
done
sanitize_cards
ensure_front_scaffold 2>/dev/null
    DONE_LOG="$(git log --format=%s "$BASE"..HEAD 2>/dev/null)"
    for q in loop/state/queue/*.md; do
      n="$(basename "$q" .md)"
      printf '%s\n' "$DONE_LOG" | grep -q "^feat: $n \[loop" && rm -f "$q"
    done
    echo "- WARNING: state dir vanished and was self-healed (suspect: maker terminal)" >> "$REPORT"
  fi
  touch loop/state/journal.md 2>/dev/null
  # v5.9.5: LIVE deadline edit (same pattern as the STOP file). Anytime during a run:
  #   echo '+2h'   > <main>/loop/DEADLINE    extend 2h from now
  #   echo '17:30' > <main>/loop/DEADLINE    absolute time (tomorrow if already past)
  # Consumed one-shot at the next cycle boundary; unparseable content is ignored.
  if [ -f "$MAIN/loop/DEADLINE" ]; then
    NEW_DL="$(head -1 "$MAIN/loop/DEADLINE" | tr -d '[:space:]')"; nd=""
    if [[ "$NEW_DL" =~ ^\+([0-9]+)h$ ]]; then nd=$(( $(date +%s) + ${BASH_REMATCH[1]} * 3600 ))
    elif [[ "$NEW_DL" =~ ^[0-9]{1,2}:[0-9]{2}$ ]]; then
      nd="$(date -j -f "%Y-%m-%d %H:%M" "$(date +%Y-%m-%d) $NEW_DL" +%s 2>/dev/null)"
      [ -n "$nd" ] && [ "$nd" -le "$(date +%s)" ] && nd=$(( nd + 86400 ))
    fi
    if [ -n "$nd" ]; then
      deadline="$nd"
      echo "[loop] deadline UPDATED live -> $(date -r "$deadline")"
      echo "- deadline updated live to $(date -r "$deadline")" >> "$REPORT"
    else
      echo "[loop] DEADLINE file unparseable ('$NEW_DL'), ignored (use +Nh or HH:MM)"
    fi
    rm -f "$MAIN/loop/DEADLINE"
  fi
  [ -f "$STOP" ] && { echo "[loop] STOP file"; echo "- STOP file" >> "$REPORT"; rm -f "$MAIN/loop/NIGHT-PLAN"; break; }
  [ "$(date +%s)" -ge "$deadline" ] && { echo "[loop] deadline reached"; rm -f "$MAIN/loop/NIGHT-PLAN"; break; }
  [ $(( deadline - $(date +%s) )) -lt "$MIN_SLACK" ] && { echo "[loop] <20m to deadline, stopping"; echo "- stopped (deadline slack)" >> "$REPORT"; break; }
  # v6.39: le BREAKER ne stoppe plus le run. Les echecs durs consecutifs sont deja bankes
  # et routes individuellement (park/fail/carry); on notifie, on remet le compteur, on
  # CONTINUE. La deadline est la seule fin legitime (avec STOP humain).
  [ "$consec" -ge "$K_BREAK" ] && { echo "[loop] breaker: $consec hard failures, cartes routees, le run CONTINUE"; echo "- BREAKER: $consec echecs durs consecutifs, routes, run poursuivi" >> "$REPORT"; notify_phone "⚠️ $consec echecs durs consecutifs: cartes bankees et routees, le loop continue (pas d'arret)."; consec=0; }

  # v6.56 GARDE STERILE (auto-detection du construire-et-reverter, defaut 12/07): si les
  # cycles avancent de STERILE_K sans UN SEUL vert, ce n'est pas la difficulte des cartes,
  # c'est systemique (probes cassees, gate KO, tout faux-rouge). Le loop CRIE (autopsie +
  # Telegram dedoublonne) et CONTINUE (pauser une nuit = nuit perdue, regle proprietaire:
  # il faut essayer, pas dormir). runnable_probes soigne deja la cause n1 (probes prose);
  # ceci attrape le reste et reveille l'operateur pour fixer en parallele.
  if [ "$cyc" -ge "${STERILE_K:-5}" ] && [ $(( cyc - last_green_cyc )) -ge "${STERILE_K:-5}" ] && [ "$sterile_notified" = 0 ]; then
    _SA="$(autopsy)"
    echo "[loop] RUN STERILE: $(( cyc - last_green_cyc )) cycles sans vert. Cause probable: $_SA"
    echo "- RUN STERILE ($(( cyc - last_green_cyc )) cycles sans vert): $_SA" >> "$REPORT"
    notify_phone "RUN STERILE ($(basename "$MAIN")): $(( cyc - last_green_cyc )) cycles, 0 vert. $_SA. Le loop CONTINUE, a verifier."
    sterile_notified=1
  fi
  mem_police   # v6.39: sous MLX, aucun modele ollama residuel (un seul LLM local)
  # v6.15: sentinelle quota (frontier seulement, lit le log du cycle precedent)
  _LAST_CYCLE_LOG="$(ls -t loop/logs/cycle-*.log 2>/dev/null | head -1)"
  [ -n "$_LAST_CYCLE_LOG" ] && usage_watch "$_LAST_CYCLE_LOG"
  # v6.6: l'humain a peut-etre ecrit pendant le run
  consume_feedback
  CARD="$(pick_card)"
  if [ -z "$CARD" ]; then
    # v6.47: file non vide mais tout en cooldown => on ATTEND (5min), on ne declare ni
    # fini ni carto: les cartes reviennent quand leur horloge expire.
    if [ "$(ls loop/state/queue/*.md 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ]; then
      echo "[loop] toutes les cartes en cooldown, pause 5min"; sleep 300; continue
    fi
    if cartographer; then continue; fi
    # v6.6: CANDIDAT FINI, couverture 100% verte + file vide + carto sans nouvelle carte.
    # Candidat seulement: l'humain confirme au matin, le loop ne declare pas la victoire seul.
    if [ -f docs/coverage.md ]; then
      _covt="$(( $(grep -c '^|' docs/coverage.md) - 2 ))"; _covv="$(grep -c 'COUVERT-VERT' docs/coverage.md)"
      if [ "$_covt" -gt 0 ] && [ "$_covv" -ge "$_covt" ] && [ ! -f loop/DONE-CANDIDATE ]; then
        { echo "Candidat FINI declare le $(date '+%F %H:%M')"; echo "Couverture: $_covv/$_covt use cases verts, file vide, cartographe sans nouvelle carte."; } > loop/DONE-CANDIDATE
        git add loop/DONE-CANDIDATE >/dev/null 2>&1; git commit -qm "loop: CANDIDAT FINI declare [loop]" >/dev/null 2>&1 || true
        echo "- CANDIDAT FINI declare (couverture $_covv/$_covt)" >> "$REPORT"
        notify_phone "🏁 CANDIDAT FINI: couverture 100% verte, file vide, cartographe a sec. Verifie au matin, ton veto fait foi."
      fi
    fi
    # v6.67 (nuit du 16/07): la sortie "queue complete" ne purgait PAS NIGHT-PLAN. Le run
    # 8h a fini son travail a 02:50 (file videe, cloture propre), mais la deadline 06:51
    # restait ecrite: le resurrecteur (tick 5min) a vu "deadline future + driver mort" et
    # a relance EN BOUCLE une nuit deja terminee (02:5x, 05:36, 05:41, 05:46). Un travail
    # FINI est une fin legitime au meme titre que la deadline: on purge le plan.
    echo "[loop] queue complete"; echo "- queue complete" >> "$REPORT"; rm -f "$MAIN/loop/NIGHT-PLAN"; lot_close; break
  fi
  NAME="$(basename "$CARD" .md)"
  # v6.0: close + review the open lot when the NEXT card belongs to a different cluster
  if [ "${LOOP_REVIEW:-lot}" = "lot" ] && lot_open; then
    _next="$(base_name "$NAME")"
    if [ "$(cluster_of "$_next")" != "$LOT_CLUSTER" ]; then lot_close; fi
  fi
  export VERIFY_SCOPE="$(grep -m1 '^SCOPE:' "$CARD" 2>/dev/null | awk '{print $2}')"
  [ -z "$VERIFY_SCOPE" ] && export VERIFY_SCOPE=full

  # pre-PROBE short-circuit: all probes already pass => card done, zero model time.
  # v6.56: exiger au moins un probe EXECUTABLE (runnable_probes non vide). Une carte a
  # probes uniquement en prose donnerait zero probe testable => l'ancien grep -q la
  # faisait AUTODONE a tort (marquee faite sans rien construire). Garde: pas de raccourci
  # sans un vrai probe a evaluer.
  # v6.81 (27/07, faute d'auteur reproduite: une carte de REPARATION ecrite a la main
  # apres un e2e rouge portait des probes tous deja verts (test -f de fichiers existants,
  # gates qui passaient deja) => AUTODONE au semis, carte marquee faite, 13 specs toujours
  # rouges. Regle: une carte de REPARATION decrit un defaut CONSTATE. Si ses probes passent
  # deja, la seule conclusion saine est que les PROBES sont mauvais, jamais que le defaut
  # a disparu tout seul. AUTODONE leur est donc interdit par nature: elles passent par le
  # maker et par le gate, qui jugent le travail reel.
  case "$(base_name "$NAME")" in
    00-F*|00-E2E*|zz-E-*)
      if [ -n "$(runnable_probes "$CARD")" ]; then
        _rep_all=1
        while IFS= read -r probe; do [ -z "$probe" ] && continue
          case "$probe" in *"playwright test"*) continue ;; esac
          timeout 30 bash -c "$probe" >/dev/null 2>&1 || { _rep_all=0; break; }
        done < <(runnable_probes "$CARD")
        [ "$_rep_all" = 1 ] && echo "[loop] carte de REPARATION $NAME: tous ses probes passent DEJA => probes non discriminants, AUTODONE refuse, elle passe par maker + gate" \
          && echo "- $NAME: probes non discriminants (reparation), AUTODONE refuse" >> "$REPORT"
      fi ;;
  esac
  case "$(base_name "$NAME")" in 00-F*|00-E2E*|zz-E-*) _no_autodone=1 ;; *) _no_autodone=0 ;; esac
  if [ "$_no_autodone" = 0 ] && [ -n "$(runnable_probes "$CARD")" ] && ! card_has_or_probes "$CARD"; then
    ALL_PASS=1
    while IFS= read -r probe; do [ -z "$probe" ] && continue   # v6.56: runnable_probes a deja strip+neutralise
      case "$probe" in *"playwright test"*) continue ;; esac  # v6.51.3: l'EXECUTION e2e appartient au harnais (phase e2e: ports+temps); inline = EPERM sandbox ou timeout court = faux rouge garanti (pilote: 4 cartes finies jetees)
      timeout 30 bash -c "$probe" >/dev/null 2>&1 || { ALL_PASS=0; break; }
    done < <(runnable_probes "$CARD")
    if [ "$ALL_PASS" = "1" ]; then
      echo "[loop] AUTODONE (probes already pass): $NAME"; mv "$CARD" loop/state/done/
      echo "- $NAME: AUTODONE" >> "$REPORT"; printf -- '- [driver] %s AUTODONE\n' "$NAME" >> "$JOURNAL"; continue
    fi
  fi

  # defer-hard-cards (v5.7.2): a card that ENTERED already marked hard (LESSONS from a
  # prior night, or ESCALATED) runs LAST so it never blocks fresh/easy cards. Deferred
  # once (zz-H- prefix, sorts after zz-D-). zz-E- (deferred escalation retry) is exempt,
  # it must run with the escalation maker, not be re-deferred.
  if [[ "$NAME" != zz-H-* ]] && [[ "$NAME" != zz-E-* ]] && grep -qE '^ESCALATED:|^## LESSONS' "$CARD" 2>/dev/null; then
    # v6.41: un DEFER-HARD REPETE = carte trop grosse qui boucle. Au 2e, elle part au
    # decoupage (park + SPLIT-REQUEST, mecanisme v6.23) au lieu de tourner au tail a vie.
    mkdir -p loop/state/deferhard
    _dhc_f="loop/state/deferhard/$(base_name "$NAME").count"
    _dhc=$(( $(cat "$_dhc_f" 2>/dev/null || echo 0) + 1 )); echo "$_dhc" > "$_dhc_f"
    if [ "$_dhc" -ge 2 ]; then
      _orig="$(base_name "$NAME")"
      mkdir -p loop/state/parked
      { printf '\nSPLIT-REQUEST: parked %s apres %s defer-hard, le cartographe doit decouper en sous-cartes\n' "$(date +%F)" "$_dhc"; } >> "loop/tasks/$_orig.md" 2>/dev/null
      mv "loop/tasks/$_orig.md" "loop/state/parked/$_orig.md" 2>/dev/null
      mv "$CARD" "loop/state/parked/queue-$_orig.md" 2>/dev/null
      rm -f "$_dhc_f"
      echo "[loop] PARK+SPLIT: $_orig (defer-hard x$_dhc), le cartographe la decoupera"
      echo "- $_orig: PARKED pour decoupage (defer-hard x$_dhc)" >> "$REPORT"
      continue
    fi
    echo "[loop] DEFER-HARD (carries lessons/escalation): $NAME -> tail ($_dhc/2 avant decoupage)"
    mv "$CARD" "loop/state/queue/zz-H-$(base_name "$NAME").md"
    echo "- $NAME: deferred (hard, runs last)" >> "$REPORT"; continue
  fi

  # DAG-lite: defer a card whose DEPENDS target has no green commit yet (once)
  DEP="$(grep -m1 '^DEPENDS:' "$CARD" 2>/dev/null | awk '{print $2}')"
  if [ -n "$DEP" ] && [[ "$NAME" != zz-D-* ]]; then
    if ! git log --format=%s "$BASE"..HEAD 2>/dev/null | grep -q "^feat: $DEP \[loop"; then
      echo "[loop] DEFER (depends on $DEP): $NAME"; mv "$CARD" "loop/state/queue/zz-D-$(base_name "$NAME").md"
      echo "- $NAME: deferred (depends on $DEP)" >> "$REPORT"; continue
    fi
  fi

  # maker selection: ESCALATED tier (or zz-E-) => escalation maker; MAKER: preference
  # keeps the ladder; else default. (review OV-10)
  CARD_ESC="$(grep -m1 '^ESCALATED:' "$CARD" 2>/dev/null | awk '{print $2}')"
  CARD_MAKER="$(grep -m1 '^MAKER:' "$CARD" 2>/dev/null | awk '{print $2}')"
  if [[ "$NAME" == zz-E-* ]] || [ -n "$CARD_ESC" ]; then
    # v6.22 BUG A: un tag ESCALATED perime d'un run precedent (ex opus) ne doit PAS
    # ressusciter sa famille sous un run d'une autre famille (ex codex). Le tag n'est
    # honore que si sa famille correspond a l'escalade du run courant; sinon l'escalade
    # du run (qui suit LOOP_MAKER_KIND / LOOP_ESCALATION_MAKER) gagne.
    if [ -n "$CARD_ESC" ] && [ "$(esc_family "$CARD_ESC")" = "$(esc_family "$ESCALATION_MAKER")" ]; then
      export LOOP_MAKER="$CARD_ESC"
    else
      export LOOP_MAKER="$ESCALATION_MAKER"
    fi
  elif [ -n "$CARD_MAKER" ]; then export LOOP_MAKER="$CARD_MAKER"
  else export LOOP_MAKER="$DEFAULT_MAKER"; fi   # v6.1.1: explicit, never fall to run-cycle's own default (MLX runs mis-named otherwise)
  swap_local "$LOOP_MAKER"   # v6.36: un seul modele local resident (swap MLX <-> ollama)
  COMMIT_NAME="$(base_name "$NAME")"
  cyc=$(( cyc + 1 )); T0=$(date +%s)
  # v6.19: famille effective du maker de cette carte (le "3x codex vs opus" devient DONNEE)
  case "$LOOP_MAKER" in
    claude-*|*opus*|*sonnet*|*haiku*) PERF_KIND=claude ;;
    codex|gpt-*|o1-*|o3-*|o4-*)        PERF_KIND=codex ;;
    *) PERF_KIND="${LOOP_MAKER_KIND:-hermes}" ;;
  esac
  PERF_MODEL="$LOOP_MAKER"
  [ "$PERF_KIND" = "claude" ] && PERF_MODEL="$LOOP_MAKER@${LOOP_CLAUDE_EFFORT:-medium}"   # v6.40: l'effort fait partie de la mesure
  echo "[loop] === cycle $cyc: $NAME (scope=$VERIFY_SCOPE maker=${LOOP_MAKER:-$DEFAULT_MAKER}) ==="

  # v5.9.1/.4: stage the previous failed attempt + why it failed for the maker to continue
  rm -f loop/state/wip-current.patch loop/state/wip-current.findings
  [ -f "$MAIN/loop/wip/$COMMIT_NAME.patch" ] && cp "$MAIN/loop/wip/$COMMIT_NAME.patch" loop/state/wip-current.patch \
    && echo "[loop] retry has previous attempt staged ($(wc -c < loop/state/wip-current.patch | tr -d ' ') bytes)"
  [ -f "$MAIN/loop/wip/$COMMIT_NAME.findings.txt" ] && cp "$MAIN/loop/wip/$COMMIT_NAME.findings.txt" loop/state/wip-current.findings

  # v5.9.6: a card's BUDGET (e.g. 'BUDGET: 3h' for a long analysis) raises this cycle's
  # wrapper timeout too, else the 75m cap would kill the budgeted work from outside.
  CYC_TO="$CYCLE_TIMEOUT"
  CB="$(grep -m1 '^BUDGET:' "$CARD" 2>/dev/null | awk '{print $2}')"
  if [ -n "$CB" ]; then
    case "$CB" in *h) CBS=$(( ${CB%h} * 3600 )) ;; *m) CBS=$(( ${CB%m} * 60 )) ;; *) CBS="$CB" ;; esac
    [ "$CBS" -gt 0 ] 2>/dev/null && [ $(( CBS + 1200 )) -gt "$CYC_TO" ] && CYC_TO=$(( CBS + 1200 ))
  fi

  quota_gate   # v6.52: evaluer AVANT de depenser (jamais apres l'echec)
  attempt=0; rc=0
  while :; do
    if [ "${LOOP_REVIEW:-lot}" = "lot" ]; then
      LOOP_CHECKER=off timeout "$CYC_TO" ./loop/run-cycle.sh "$CARD"; rc=$?
    else
      timeout "$CYC_TO" ./loop/run-cycle.sh "$CARD"; rc=$?
    fi
    [ "$rc" -ne 124 ] && break
    attempt=$(( attempt + 1 )); echo "[loop] watchdog kill, restart $attempt/$N_RESTART (work PRESERVED, session continues from it)"
    [ "$attempt" -ge "$N_RESTART" ] && break
    # v5.9.1: do NOT wipe on restart. The old `git checkout -- . && git clean -fd` here
    # DESTROYED up to 30min of half-built work and restarted the card from zero (3x for
    # some cards). The fresh session reads the existing files and continues; the gate
    # still reverts atomically at cycle end if the result fails.
    ollama stop "$DEFAULT_MAKER" 2>/dev/null
  done
  DUR=$(( ( $(date +%s) - T0 ) / 60 )); DUR_S=$(( $(date +%s) - T0 ))

  # STOP-interruption (afk return / kill) is NOT a card failure: requeue untouched, stop.
  if [ -f "$STOP" ]; then
    echo "[loop] STOP during cycle, requeuing $NAME untouched"
    git reset --hard HEAD >/dev/null 2>&1; git clean -fd -e loop >/dev/null 2>&1
    echo "- $NAME: interrupted (STOP), requeued" >> "$REPORT"; break
  fi

  CHK="$(cat loop/state/verdict.last 2>/dev/null || echo none)"
  REP="$(grep -c "\[repair\] $NAME " "$JOURNAL" 2>/dev/null | tail -1)"
  RRL="$(grep -c "\[reroll\] $NAME " "$JOURNAL" 2>/dev/null | tail -1)"

  if [ "$rc" -ne 0 ]; then
    echo "[loop] HARD-FAIL rc=$rc (${DUR}m)"; git reset --hard HEAD >/dev/null 2>&1; git clean -fd -e loop >/dev/null 2>&1
    # v6.47 BUG D (pilote, 24 HARD-FAIL rc=1 en 0m: quota codex mort EN run, la
    # doctrine muet v6.39 n'etait cablee que pour hermes/MLX): un echec INSTANTANE n'est
    # jamais le code. 2 consecutifs <60s => sonde directe du maker; muet => QUOTA-PAUSE
    # (carte NI accusee NI routee, retentee a la reprise). Vivant => echec reel, route.
    if [ "${DUR_S:-999}" -lt 60 ]; then FF_N=$(( ${FF_N:-0} + 1 )); else FF_N=0; fi
    if [ "${FF_N:-0}" -ge 2 ] && ! maker_ping; then
      echo "[loop] fast-fail x$FF_N et maker MUET a la sonde: c'est l'infra/quota, pas la carte"
      quota_pause; FF_N=0; continue
    fi
    # v6.50.5 (nuit du 10/07: la machine a PERDU INTERNET ~02:00; le CLI maker retente
    # ~12min puis meurt en ConnectionRefused: trop LENT pour la sentinelle <60s ci-dessus,
    # 6 cycles brules au lieu d une pause). L INTERNET SE TRAVERSE COMME LA NUIT: HARD-FAIL
    # avec signature reseau dans le log de cycle + endpoint API injoignable => pause par
    # tranches de 5min jusqu au retour du reseau (bornee deadline), carte NI accusee NI
    # routee. Telegram APRES reconnexion (pendant la coupure il ne partirait pas).
    _NLC="$(ls -t loop/logs/cycle-*.log 2>/dev/null | head -1)"
    if [ -n "$_NLC" ] && tail -8 "$_NLC" | grep -qiE 'Unable to connect|ConnectionRefused|ENOTFOUND|ETIMEDOUT|network is unreachable'        && ! curl -sI --max-time 8 https://api.anthropic.com >/dev/null 2>&1; then
      NET_T0=$(date +%s)
      echo "[loop] INTERNET PERDU (signature reseau + endpoint injoignable): pause 5min en boucle jusqu au retour"
      while [ $(( deadline - $(date +%s) )) -gt 700 ]; do
        sleep 300
        curl -sI --max-time 8 https://api.anthropic.com >/dev/null 2>&1 && break
        echo "[loop] internet toujours absent, nouvelle pause 5min"
      done
      if curl -sI --max-time 8 https://api.anthropic.com >/dev/null 2>&1; then
        echo "[loop] INTERNET REVENU apres $(( ($(date +%s) - NET_T0) / 60 ))min, reprise (carte retentee)"
        echo "- COUPURE INTERNET: $(( ($(date +%s) - NET_T0) / 60 ))min, cartes preservees" >> "$REPORT"
        notify_phone "🌐 Internet perdu $(( ($(date +%s) - NET_T0) / 60 ))min pendant le run ($(basename "$MAIN")): pause auto, aucune carte accusee, reprise."
      fi
      FF_N=0; continue
    fi
    # v6.79 (run 27/07, cycle 1: "API Error: 529 Overloaded" apres 13min de travail =>
    # HARD-FAIL, carte accusee a tort, 13min perdues). Un 529/503 n'est ni le code, ni le
    # quota, ni le reseau: c'est le fournisseur SATURE, transitoire par nature (l'endpoint
    # REPOND, donc la garde reseau ci-dessus ne le voit pas, et la sonde rate-limit ne
    # connait que les 429). Meme doctrine que la coupure internet: courte pause, carte NI
    # accusee NI routee, retentee. Plafond de 3 episodes par run: au-dela on route
    # normalement (une carte qui provoque SYSTEMATIQUEMENT un 529 est suspecte).
    if [ -n "$_NLC" ] && tail -12 "$_NLC" | grep -qiE '\b529\b|overloaded|service unavailable|\b503\b|internal server error' \
       && [ "${OVL_N:-0}" -lt 3 ]; then
      OVL_N=$(( ${OVL_N:-0} + 1 ))
      echo "[loop] FOURNISSEUR SATURE (529/503, episode $OVL_N/3): panne transitoire, pas la carte. Pause 3min, carte PRESERVEE et retentee."
      echo "- FOURNISSEUR SATURE (529/503) sur $NAME: pause 3min, carte preservee (episode $OVL_N/3)" >> "$REPORT"
      [ $(( deadline - $(date +%s) )) -gt 400 ] && sleep 180
      FF_N=0; continue
    fi
    perf_log HARD "$DUR_S"; route_failure "$CARD" "$NAME" "HARD-FAIL rc=$rc ${DUR}m"; hard_c=$(( hard_c + 1 )); consec=$(( consec + 1 )); continue
  fi
  consec=0

  if [ -z "$(git status --porcelain)" ] && ! sidecar_dirty; then   # v6.62.1: sidecar sale = vrai changement
    # v6.66 (rapport pilote 16/07, faux positif qui a failli bruler 7h): un no-change a
    # DEUX causes OPPOSEES a ne jamais confondre. (a) maker MUET/mort = vraie panne infra.
    # (b) maker exit=0 qui ne change RIEN parce que la carte est DEJA SATISFAITE = succes.
    # L'ancienne loi tranchait par model_alive() AVANT de tester la carte -- et model_alive
    # sonde ollama/MLX meme quand le maker est codex/claude: chez pilote (maker codex,
    # ollama eteint) la sonde disait "mort" -> branche infra -> HEAL en boucle 7h sur une
    # carte deja construite et mergee. FIX (proposition pilote #1): tester la CARTE
    # d'abord. Vert en historique OU probes bruts tous verts => FAITE, on classe et on
    # avance, quelle que soit la couche modele. Un exit=0 avec probes verts = AUTODONE
    # tardif, JAMAIS une panne. On ne descend a la garde infra que si la carte n'est PAS
    # satisfaite (la, un vrai mutisme merite pause/heal).
    if git log --format=%s "$BASE"..HEAD "$BASE" 2>/dev/null | grep -q "^feat: $COMMIT_NAME \[loop"; then
      echo "[loop] NOOP-DONE: $NAME deja satisfaite (verte en historique), rien a changer"
      echo "- $NAME: NOOP-DONE (deja verte, aucun changement requis)" >> "$REPORT"
      printf -- '- [driver] %s NOOP-DONE (deja verte)\n' "$NAME" >> "$JOURNAL"
      mv "$CARD" "loop/state/done/$(base_name "$NAME").md" 2>/dev/null
      infra_c=0; consec=0; continue
    fi
    # v6.81: meme interdit pour les cartes de reparation (voir la garde au pick).
    if [ "${_no_autodone:-0}" = 0 ] && ! card_has_or_probes "$CARD" && raw_probes_all_pass "$CARD"; then
      echo "[loop] AUTODONE-LATE: $NAME no-change mais TOUS ses probes bruts passent (feature deja livree)"
      echo "- $NAME: AUTODONE-LATE (no-change, probes bruts tous verts)" >> "$REPORT"
      printf -- '- [driver] %s AUTODONE-LATE\n' "$NAME" >> "$JOURNAL"
      mv "$CARD" "loop/state/done/$(base_name "$NAME").md" 2>/dev/null
      infra_c=0; consec=0; continue
    fi
    # Carte NON satisfaite + zero diff: maintenant seulement on distingue muet vs infra.
    # v6.2.1 infra guard: a no-change session that died in seconds is an INFRA symptom
    # (model not loaded / server down), not a card failure. Hold and retry the same card;
    # 3 strikes = stop loudly. Never let a dead model masquerade as 15 bad cards.
    if [ "$DUR" -lt 2 ]; then
      # v6.66: la sonde model_alive ne vaut QUE pour un maker local (ollama/MLX). Pour un
      # maker frontier (codex/claude), un exit=0 avec sortie de travail NON VIDE prouve
      # que le maker est vivant (rapport pilote #3): ne jamais escalader "couche modele
      # morte" sur un exit verbeux. On lit le dernier cycle log: s'il contient une reponse
      # substantielle, le maker vit, le no-change est un vrai "rien a faire" -> route no-change.
      _CKL="$(ls -t loop/logs/cycle-*.log 2>/dev/null | head -1)"
      _MAKER_VERBOSE=""
      [ -n "$_CKL" ] && [ "$(sed -n '/########## RESPONSE ##########/,$p' "$_CKL" 2>/dev/null | wc -c | tr -d ' ')" -gt 200 ] && _MAKER_VERBOSE=1
      if [ "${LOOP_MAKER_KIND:-hermes}" != "hermes" ] && [ -n "$_MAKER_VERBOSE" ]; then
        echo "[loop] no change (${DUR}m) mais maker frontier VERBEUX (exit=0, reponse non vide): vivant, rien a faire sur cette carte, PAS d'infra"
        infra_c=0; route_failure "$CARD" "$NAME" "no-change verbeux ${DUR}m"; skip_c=$(( skip_c + 1 )); continue
      fi
      if model_alive; then
        mute_c=$(( ${mute_c:-0} + 1 ))
        # v6.49.1 (rapport pilote, run all-Opus pendant un incident API Anthropic:
        # BEAUCOUP de Telegram muet x3). Avant l'escalier: si le log de cycle montre une
        # signature de PANNE FOURNISSEUR (API/quota/overload) ET que le maker ne repond
        # plus a une sonde directe, ce n'est ni le profil ni la carte: c'est l'API qui
        # flanche. On PAUSE (quota_pause: dedup Telegram + attente + reprise auto) au lieu
        # de bruler carte apres carte avec une alerte chacune. La sentinelle attend la fin
        # de l'incident, elle ne spamme pas. maker_ping = le VRAI chemin maker (v6.49).
        _MLC="$(ls -t loop/logs/cycle-*.log 2>/dev/null | head -1)"
        if [ -n "$_MLC" ] && tail -6 "$_MLC" | grep -qiE 'API call failed|overloaded|rate.?limit|usage limit|529|503|temporarily unavailable|try again at' && ! maker_ping; then
          echo "[loop] muet = PANNE FOURNISSEUR (API/quota, sonde maker muette): pause au lieu de defer-spam"
          quota_pause; mute_c=0; route_c=0; continue
        fi
        # v6.42: LIRE LA RAISON avant de compter. La nuit du 08/07 (96 cycles a vide),
        # chaque log de cycle finissait par "API call failed after 3 retries: HTTP 404:
        # model ... not found": panne de ROUTAGE hermes->provider (profil user ignorant le
        # nom MLX), pas un maker muet. Le remede est regen + RE-ADOPTION du profil loop,
        # pas defer. Un vrai muet (API saine, zero diff) suit l'escalier x2/x3 d'origine.
        # Plafond 2 reparations routage par carte: au-dela on laisse l'escalier x2/x3
        # deferer (sinon un 404 persistant referait le tapis roulant, diagnostic en plus).
        _LCL="$(ls -t loop/logs/cycle-*.log 2>/dev/null | head -1)"
        if [ -n "$_LCL" ] && [ "${route_c:-0}" -lt 2 ] && tail -5 "$_LCL" | grep -qE 'API call failed|HTTP 4[0-9][0-9]|model .* not found|[Cc]ontext (length|window)'; then
          route_c=$(( ${route_c:-0} + 1 ))
          echo "[loop] muet = panne de routage API (tail du cycle, reparation $route_c/2): regen profil + re-adoption"
          if bash "$MAIN/loop/setup-hermes-profile.sh" "$WT"; then
            export LOOP_HERMES_HOME="${LOOP_PROFILE_DIR:-$HOME/.hermes-loop-cdc}"
            echo "[loop] profil loop re-adopte (LOOP_HERMES_HOME exporte)"
          else
            heal_model_layer   # smoke encore KO: recharge modele (65536) puis on reverra
          fi
          sleep 15; continue
        fi
        if [ "$mute_c" -eq 2 ]; then
          # v6.39 AUTO-REPARATION: regenerer le profil hermes (l'operateur le faisait a la
          # main). Un profil corrompu est la cause la plus probable d'un maker muet.
          # v6.42: la regen doit RE-ADOPTER (export LOOP_HERMES_HOME). La nuit du 08/07,
          # ~30 regens ont reussi pour rien: la variable restait absente (le smoke initial
          # avait echoue), hermes tournait toujours sur le profil user.
          echo "[loop] maker muet x2: regeneration du profil hermes (auto-reparation)"
          if bash "$MAIN/loop/setup-hermes-profile.sh" "$WT" >/dev/null 2>&1; then
            export LOOP_HERMES_HOME="${LOOP_PROFILE_DIR:-$HOME/.hermes-loop-cdc}"
            echo "[loop] profil regenere et re-adopte"
          fi
          sleep 30; continue
        fi
        if [ "$mute_c" -ge 3 ]; then
          # v6.39: JAMAIS d'arret. La carte part en queue de file (zz-H-), on continue
          # avec la suivante. Si TOUTES mutent, la file se vide, le carto refill, et les
          # pauses bornent; la deadline est la seule fin. Telegram informe, n'exige rien.
          echo "[loop] maker muet x3 sur $NAME: defer en queue, on continue (pas d'arret)"
          echo "- $NAME: MUET x3 (modele sain), defere en queue de file" >> "$REPORT"
          mv "$CARD" "loop/state/queue/zz-H-$(base_name "$NAME").md" 2>/dev/null
          # v6.49.1: Telegram DEDOUBLONNE (1x/heure, meme discipline que l'infra ligne
          # ~1736 et le quota). Un episode muet qui touche N cartes = UNE alerte, pas N.
          _now_m=$(date +%s)
          if [ $(( _now_m - ${mute_last_notify:-0} )) -gt 3600 ]; then
            notify_phone "🔇 Cartes muettes (modele sain) chez $(basename "$MAIN"): defer + continue. 1 alerte/heure max pendant l'episode. Le loop ne s'arrete pas."
            mute_last_notify=$_now_m
          fi
          mute_c=0; route_c=0; infra_c=0; continue
        fi
        echo "[loop] maker muet ($mute_c/3) avec modele sain: retry 60s"
        sleep 60; continue
      fi
      infra_c=$(( ${infra_c:-0} + 1 ))
      if [ "$infra_c" -ge 3 ]; then
        # v6.3: pause-and-probe avant d'abandonner. Le mur de 03:52 etait TRANSITOIRE
        # (RAM au rechargement ornith); 10 minutes plus tard le modele rechargeait
        # proprement. On patiente donc jusqu'a 3 x 10 min en re-sondant la couche
        # modele, et on ne s'arrete que si elle reste morte.
        # v6.39: NE JAMAIS S'ARRETER avant la deadline. HEAL d'abord (la reparation que
        # l'operateur faisait a la main), puis pause 10min et on RE-ESSAIE, indefiniment,
        # bornes par la deadline seule. Telegram au plus 1x/heure pour ne pas spammer.
        if heal_model_layer; then infra_c=0; continue; fi
        infra_pause=$(( ${infra_pause:-0} + 1 ))
        now_h=$(date +%s)
        if [ $(( now_h - ${infra_last_notify:-0} )) -gt 3600 ]; then
          notify_phone "⏸️ Loop: couche modele morte (pause $infra_pause), auto-heal en boucle jusqu'a la deadline. Aucun arret."
          infra_last_notify=$now_h
        fi
        echo "[loop] INFRA: pause $infra_pause (10min), heal+re-sonde en continu jusqu'a la deadline"
        [ $(( deadline - $(date +%s) )) -lt 700 ] && { echo "[loop] deadline proche, fin de fenetre"; break; }
        sleep 600
        infra_c=0
        continue
      fi
      echo "[loop] no change in ${DUR}m: infra suspect ($infra_c/3), holding 60s and retrying same card"
      sleep 60; continue
    fi
    infra_c=0
    echo "[loop] no change (${DUR}m)"; route_failure "$CARD" "$NAME" "no-change ${DUR}m"; skip_c=$(( skip_c + 1 )); continue
  fi

  # fast-RED: unrecovered compile errors (run-cycle already skipped checker+verify)
  if [ "$CHK" = "REDCOMPILE" ]; then
    echo "[loop] fast-RED compile (${DUR}m), reverting"; perf_log REDCOMPILE "$DUR_S"; bank_wip "$COMMIT_NAME" REDCOMPILE; git reset --hard HEAD >/dev/null; git clean -fd -e loop >/dev/null
    route_failure "$CARD" "$NAME" "REDCOMPILE ${DUR}m"; red_c=$(( red_c + 1 ))
    # v6.46 point 3 (cahier pilote): LIRE nos propres diagnostics. 3 echecs consecutifs
    # a signature IDENTIQUE = suspicion harnais (les 9 faux REDCOMPILE partageaient
    # 'bash: -c: syntax error' 9 fois, le maker l'avait meme ecrit en toutes lettres).
    # Verdict par gate_selftest sur l'arbre reverte (connu-bon): s'il echoue, c'est le
    # harnais, pause-heal 10min jusqu'a reparation ou deadline, AUCUNE carte accusee.
    _sig="$(sig_of_last_cycle)"
    if [ -n "$_sig" ] && [ "$_sig" = "${SIG_LAST:-}" ]; then SIG_N=$(( ${SIG_N:-0} + 1 )); else SIG_LAST="$_sig"; SIG_N=1; fi
    if [ "${SIG_N:-0}" -ge 3 ]; then
      echo "[loop] BREAKER: 3 echecs consecutifs, signature identique: $_sig"
      if gate_selftest; then
        echo "[loop] BREAKER: harnais SAIN (gate vert sur arbre reverte), echecs reels, on continue"
        SIG_N=0
      else
        notify_phone "🚨 HARNAIS CASSE EN RUN ($(basename "$MAIN")): signature x3 '$_sig', gate rouge sur arbre connu-bon. Cartes en pause, re-test toutes les 10min jusqu'a reparation ou deadline. Aucune carte accusee."
        echo "- BREAKER: harnais casse en run (signature: $_sig), cartes en pause-heal" >> "$REPORT"
        while [ $(( deadline - $(date +%s) )) -gt 700 ]; do
          sleep 600
          heal_model_layer >/dev/null 2>&1
          gate_selftest && { echo "[loop] BREAKER: harnais repare, reprise des cartes"; SIG_N=0; break; }
          echo "[loop] BREAKER: harnais toujours casse, nouvelle pause 10min"
        done
      fi
    fi
    continue
  fi
  # BLOCKING checker: FAIL kills the increment before the expensive verify
  if [ "$CHK" = "FAIL" ]; then
    # v5.9.7 PROBE-GAP detector: if the card's own PROBEs all pass on the tree the checker
    # just REJECTED, the probes are weaker than the card's real DONE WHEN, the maker
    # satisfied the probes and stopped short (the 24-etape signature). Recorded for the
    # distiller, which proposes tightened probes (one per DONE WHEN criterion).
    PG=1
    while IFS= read -r probe; do [ -z "$probe" ] && continue   # v6.56: runnable_probes a deja strip+neutralise
      case "$probe" in *"playwright test"*) continue ;; esac  # v6.51.3: l'EXECUTION e2e appartient au harnais (phase e2e: ports+temps); inline = EPERM sandbox ou timeout court = faux rouge garanti (pilote: 4 cartes finies jetees)
      ( eval "$probe" ) >/dev/null 2>&1 || { PG=0; break; }
    done < <(runnable_probes "$CARD")
    if [ "$PG" = 1 ] && grep -q '^PROBE: ' "$CARD" 2>/dev/null; then
      echo "[loop] PROBE-GAP: $COMMIT_NAME probes all pass yet checker rejected (probes weaker than DONE WHEN)"
      echo "- PROBE-GAP: $COMMIT_NAME (probes passed, checker rejected => tighten probes, one per DONE WHEN)" >> "$REPORT"
      printf -- '- [probe-gap] %s\n' "$COMMIT_NAME" >> "$JOURNAL"
    fi
    echo "[loop] CODEX-BLOCKED (${DUR}m), reverting"; bank_wip "$COMMIT_NAME" FAIL; git reset --hard HEAD >/dev/null; git clean -fd -e loop >/dev/null
    route_failure "$CARD" "$NAME" "CODEX-BLOCKED after $RRL re-rolls ${DUR}m"; blocked_c=$(( blocked_c + 1 )); continue
  fi

  # v6.46 points 2/6: le verify final N'EST PLUS silencieux; sa sortie va en log et le
  # POURQUOI d'un RED s'affiche (avant: >/dev/null, autopsie humaine obligatoire).
  _VLOG="loop/logs/verify-final-$NAME-$(date +%H%M%S).log"
  if timeout "$VERIFY_TIMEOUT" ./loop/verify.sh >"$_VLOG" 2>&1; then
    # probe purity guard (review OV-1): probes must not mutate the tree
    PRE_H="$(tree_hash)"; PROBE_FAILED=""
    while IFS= read -r probe; do [ -z "$probe" ] && continue   # v6.56: runnable_probes a deja strip+neutralise
      case "$probe" in *"playwright test"*) continue ;; esac  # v6.51.3: l'EXECUTION e2e appartient au harnais (phase e2e: ports+temps); inline = EPERM sandbox ou timeout court = faux rouge garanti (pilote: 4 cartes finies jetees)
      timeout 60 bash -c "$probe" >/dev/null 2>&1 || { PROBE_FAILED="$probe"; break; }
    done < <(runnable_probes "$CARD")
    [ -z "$PROBE_FAILED" ] && [ "$(tree_hash)" != "$PRE_H" ] && PROBE_FAILED="(a probe mutated the tree)"
    if [ -n "$PROBE_FAILED" ]; then
      echo "[loop] PROBE FAILED (${DUR}m): $PROBE_FAILED"
      # v6.50.6: BANK avant revert (une analyse de 18min, complete et correcte,
      # detruite par un probe-fail de FORMATAGE: seuls REDCOMPILE/FAIL/no-change bankaient).
      # Un probe-fail peut etre un faux negatif: le travail se met de cote, jamais detruit.
      bank_wip "$COMMIT_NAME" PROBEFAIL
      git reset --hard HEAD >/dev/null; git clean -fd -e loop >/dev/null
      route_failure "$CARD" "$NAME" "PROBE-FAILED ${DUR}m"; red_c=$(( red_c + 1 )); continue
    fi
    # v6.50 fix #2 (pilote: FALSE-GREEN prouve, un maker a committe GREEN 5x sans code
    # produit, changements uniquement sous loop/ (reports, journal, renommages de file):
    # build+tests+probes laches passent car RIEN n'a change dans l'app). Exiger au moins un
    # changement HORS loop/ avant tout GREEN. Une carte typee doc (SCOPE: doc) est exemptee.
    _SCOPE_CARD="$(grep -m1 '^SCOPE:' "$CARD" 2>/dev/null | awk '{print tolower($2)}')"
    # v6.62.1: une carte sidecar (ou doc) est EXEMPTEE du FALSE-GREEN: son diff produit vit
    # dans le sidecar (sidecar), pas dans le worktree CDC. sidecar_dirty le prouve.
    if [ "$_SCOPE_CARD" != "doc" ] && [ "$_SCOPE_CARD" != "sidecar" ] && ! sidecar_dirty \
       && [ -z "$(git status --porcelain 2>/dev/null | awk '{print $2}' | grep -v '^loop/' | head -1)" ]; then
      echo "[loop] FALSE-GREEN bloque ($COMMIT_NAME): tous les changements sont sous loop/ (bookkeeping), zero ligne de produit; probes trop laches"
      echo "- $COMMIT_NAME: FALSE-GREEN bloque (aucun diff hors loop/, probes a resserrer)" >> "$REPORT"
      printf -- '- [false-green] %s (aucun diff produit, probes trop laches)\n' "$COMMIT_NAME" >> "$JOURNAL"
      git reset --hard HEAD >/dev/null; git clean -fd -e loop >/dev/null
      route_failure "$CARD" "$NAME" "FALSE-GREEN no product diff ${DUR}m"; red_c=$(( red_c + 1 )); continue
    fi
    # v6.73 (faille pilote 17/07: un maker ajoute une dep au manifeste, son gate lit le
    # node_modules local deja peuple donc passe vert, mais le lock jamais regenere => l'install
    # du preflight SUIVANT meurt "manifest and lock not in sync", driver mort avant cycle 1).
    # Auto-reparation PORTABLE (la loi ne connait pas npm): si le manifeste du contrat a bouge
    # et qu'un STACK_LOCK_SYNC_CMD existe, on le lance (idempotent: regenere le lock en phase
    # sans toucher node_modules) et il part dans le meme commit. Sans contrat lock -> no-op.
    if [ -n "${STACK_LOCK_SYNC_CMD:-}" ] && [ -n "${STACK_LOCK_MANIFEST:-}" ] \
       && git status --porcelain -- "$STACK_LOCK_MANIFEST" 2>/dev/null | grep -q .; then
      echo "[loop] v6.73: manifeste ($STACK_LOCK_MANIFEST) modifie -> resync du lock (contrat)"
      ( bash -c "$STACK_LOCK_SYNC_CMD" ) >/dev/null 2>&1 \
        || echo "[loop] WARN: resync du lock echoue, le preflight suivant pourrait refuser (verifier $STACK_LOCK_MANIFEST)"
    fi
    git add -A
    # v6.62.1: carte sidecar-only => rien a committer cote CDC, mais on pose un marqueur vide
    # (--allow-empty) pour que le vert compte, que le resume-skip matche, et que le commit
    # couple du sidecar s'y rattache. Sinon `git commit` echouerait sur un index vide.
    _EMPTY_OK=""; [ -z "$(git diff --cached --name-only 2>/dev/null | head -1)" ] && _EMPTY_OK="--allow-empty"
    # commit under the ORIGINAL name so resume-skip matches escalated greens (review OV-5)
    git commit -q $_EMPTY_OK -F - <<EOF
feat: $COMMIT_NAME [loop cycle $cyc]

card: $NAME
maker: ${LOOP_MAKER:-$DEFAULT_MAKER}
checker: codex $CHK (rerolls $RRL)
compile-repairs: $REP
duration-min: $DUR
verified: scoped build+tests+smoke, PROBE ok
EOF
    sha="$(git rev-parse --short HEAD)"; stat="$(git diff --stat HEAD~1..HEAD 2>/dev/null | tail -1 | sed 's/^ *//')"
    sidecar_commit "$COMMIT_NAME" "$sha"   # v6.62: commit couple du sidecar si le maker l'a touche
    mv "$CARD" loop/state/done/
    rm -f "$MAIN/loop/wip/$COMMIT_NAME.patch" "$MAIN/loop/wip/$COMMIT_NAME.findings.txt" loop/state/wip-current.patch loop/state/wip-current.findings 2>/dev/null  # v5.9.1: card done, banked attempt stale
    # v6.0: lot membership. Open the lot on its first green (base = pre-commit sha).
    if [ "${LOOP_REVIEW:-lot}" = "lot" ]; then
      if ! lot_open; then LOT_BASE="$(git rev-parse HEAD~1)"; LOT_CLUSTER="$(cluster_of "$COMMIT_NAME")"; fi
      printf '%s\t%s\n' "$COMMIT_NAME" "$sha" >> "$LOT_FILE"
      [ "$(wc -l < "$LOT_FILE" | tr -d ' ')" -ge "${LOOP_LOT_SIZE:-4}" ] && lot_close
    fi
    echo "[loop] GREEN $sha (${DUR}m, $stat)"
    perf_log GREEN "$DUR_S"; echo "- $COMMIT_NAME: GREEN $sha, ${DUR}m, $stat [codex $CHK, rerolls $RRL, repairs $REP]" >> "$REPORT"
    printf -- '- [driver] %s GREEN %s %sm\n' "$COMMIT_NAME" "$sha" "$DUR" >> "$JOURNAL"
    green_c=$(( green_c + 1 )); last_green_cyc=$cyc; sterile_notified=0   # v6.56: reset garde sterile sur un vrai vert

    if [ "$COMMIT_NAME" = "90-integration-review" ] && [ -f docs/night-review.md ]; then
      NFED="$(python3 - <<'PYEOF'
import re, os
rows = []
for line in open('docs/night-review.md', encoding='utf-8', errors='replace'):
    cells = [c.strip() for c in line.strip().strip('|').split('|')]
    if len(cells) >= 5 and re.match(r'^\d+$', cells[0]) and cells[2].upper() in ('CRITIQUE','MAJEUR'):
        rows.append(cells)
rows.sort(key=lambda c: 0 if c[2].upper()=='CRITIQUE' else 1)
os.makedirs('loop/state/queue', exist_ok=True)
n=0
for c in rows[:6]:
    n+=1
    open(f'loop/state/queue/92-fix-{n:02d}.md','w',encoding='utf-8').write(
f"""# Card 92-fix-{n:02d}, correction issue de la revue integree ({c[2]})

GOAL: fix this finding from docs/night-review.md, smallest possible change.
FILES: {c[1]}
FINDING: {c[3]}
SUGGESTED FIX: {c[4]}

Rules: touch only what this finding requires, follow existing patterns, repo must
still compile. If the finding is wrong or already fixed, write NEEDS-HUMAN and stop.
""")
print(n)
PYEOF
)"
      # persist 92-cards durably (review OV-6) + mini Phase 0 on them (review OV-7)
      cp loop/state/queue/92-fix-*.md loop/tasks/ 2>/dev/null
      git add loop/tasks/92-fix-*.md 2>/dev/null && git commit -q -m "self-feed: $NFED fix-cards from review [loop]" 2>/dev/null
      phase0_review "self-feed" "loop/state/queue/92-fix-*.md"
      echo "[loop] self-feed: $NFED durable fix-card(s)"; echo "- self-feed: $NFED fix-cards" >> "$REPORT"
    fi
  else
    echo "[loop] RED (${DUR}m), reverting"; tail -3 "$_VLOG" 2>/dev/null | sed 's/^/[verify] /'
    perf_log RED "$DUR_S"; bank_wip "$COMMIT_NAME" RED; git reset --hard HEAD >/dev/null; git clean -fd -e loop >/dev/null
    route_failure "$CARD" "$NAME" "RED ${DUR}m"; red_c=$(( red_c + 1 ))
  fi
done

RUN_H=$(( ( $(date +%s) - RUN_T0 ) / 360 ))
{ echo; echo "## Summary"
  echo "- green: $green_c   red: $red_c   codex-blocked: $blocked_c   skipped: $skip_c   hard: $hard_c   cycles: $cyc"
  echo "- metric: $green_c greens in ~$(( RUN_H / 10 )).$(( RUN_H % 10 ))h"
  echo "- remaining queue: $(ls loop/state/queue 2>/dev/null | wc -l | tr -d ' ')  failed: $(ls loop/state/failed 2>/dev/null | wc -l | tr -d ' ')  done: $(ls loop/state/done 2>/dev/null | wc -l | tr -d ' ')"
  echo "- checker log:"; grep '\[checker\].*FINAL' "$JOURNAL" | tail -40 | sed 's/^/    /'
  # v5.7.3 convergence stats: per-card findings trajectory (did re-rolls make progress?)
  echo "- convergence (findings per re-roll, dropping = good):"; grep -E '\[reroll\].*(findings|STUCK)' "$JOURNAL" | tail -30 | sed 's/^/    /'
  echo "- review: git -C $MAIN log $BASE..loop/overnight ; artifacts in $WT/loop/ (+archive in $MAIN/loop/archive/)"
  echo "- ended: $(date)"
  # v5.7 N3: Hermes usage telemetry for this run window (tokens/cost/tool patterns)
  echo "- hermes insights (1d):"; timeout 30 hermes insights --days 1 --source cli 2>/dev/null | sed 's/^/    /' | head -25; } >> "$REPORT"
# v6.0/6.2: flush the open lot on ANY exit path, then WAIT for in-flight background
# reviews (they may still queue a fix card consumed by the NEXT run's resume)
lot_close
lot_wait
bash loop/score-skills.sh "$BASE" 2>/dev/null || true
# v5.9: the learning arc. Distill this run's experience into artifacts (skills, hints,
# retired skills, metrics, proposals) so the NEXT run starts smarter. Never touches law.
# v6.7 GATE RUNTIME: une fois par run, un navigateur charge reellement les ecrans.
# Echec = carte 01-45 en tete de la prochaine file avec la preuve. SKIP = jamais bloquant.
if [ "${LOOP_E2E:-on}" = "on" ]; then
  E2E_LOG="loop/logs/e2e-$RUN.log"
  timeout 900 bash loop/e2e.sh > "$E2E_LOG" 2>&1; E2E_RC=$?
  # v6.52 PASSE FRONT-REVIEW (design proprietaire pilote: l'e2e verifie l'experience
  # ASSEMBLEE, propriete du RUN, pas d'une carte; un spec rouge devient un FINDING de
  # cette passe, jamais l'invalidation de la carte qui l'a casse). Agent configurable
  # (LOOP_FRONT_REVIEW_MODEL, defaut fable), il recoit le resultat e2e + l'annexe et emet
  # des cartes fix (le verdict spec-a-reparer vs code-a-reparer lui appartient).
  if [ "$E2E_RC" -ne 0 ] && [ "$E2E_RC" -ne 3 ] && [ "${LOOP_FRONT_REVIEW:-1}" = 1 ]; then
    _FRP="Tu es le FRONT-REVIEWER du loop. La suite e2e du run vient d'echouer. Lis le
resultat, decide pour chaque echec: le SPEC est perime (une carte a legitimement change
l'ecran) ou le CODE a casse l'experience. Emets 1-3 cartes fix (blocs ===NEW-CARD <slug>===
avec USE CASE/DONE WHEN/SCOPE: front/VALUE: P0/PROBE statiques test -f && rg, une PROBE
par token sans alternance |, JAMAIS d'execution e2e en PROBE) qui reparent le spec OU le
code selon ton verdict. VALUE: P0 obligatoire: une regression e2e prime sur toute feature.

## RESULTAT E2E
$(tail -60 "$E2E_LOG")

## REGLES PRODUIT (annexe)
$(sed -n '1,40p' docs/ameliorations.md 2>/dev/null)"
    # v6.74: le prompt front-review colle le log e2e brut (tail playwright), source la plus
    # probable d'un octet non-UTF-8 (sequence multi-octets coupee par tail -c). Le fallback
    # codex (ligne suivante) HARD-FAIL dessus. Assainir avant tout envoi (no-op si propre).
    _FRP="$(printf '%s' "$_FRP" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null || printf '%s' "$_FRP")"
    _FRO="$(timeout 300 claude ${LOOP_FRONT_REVIEW_MODEL:+--model "$LOOP_FRONT_REVIEW_MODEL"} -p "$_FRP" --output-format text 2>/dev/null)"
    [ -z "$_FRO" ] && _FRO="$(timeout 300 codex exec --sandbox read-only --skip-git-repo-check "$_FRP" 2>/dev/null)"
    if [ -n "$_FRO" ]; then
      printf '%s\n' "$_FRO" | awk '/^===NEW-CARD /{p=$0; sub(/^===NEW-CARD /,"",p); sub(/===$/,"",p); gsub(/[^a-zA-Z0-9-]/,"",p); f="loop/tasks/61-" p ".md"; inb=1; n++; if(n>3){inb=0}; next} /^===END===$/{if(inb){close(f)}; inb=0; next} inb{print >> f}'
      _FRN="$(ls loop/tasks/61-*.md 2>/dev/null | wc -l | tr -d ' ')"
      echo "[front-review] $_FRN carte(s) fix emise(s) depuis l'echec e2e"
      echo "- FRONT-REVIEW: e2e rouge analyse, cartes fix 61-* emises" >> "$REPORT"
      git add loop/tasks/61-*.md 2>/dev/null; git commit -q -m "front-review: cartes fix depuis echec e2e [loop]" 2>/dev/null
    fi
  fi
  cp "$E2E_LOG" /tmp/e2e-last.log 2>/dev/null
  case "$E2E_RC" in
    0) echo "- E2E RUNTIME: VERT (les ecrans repondent au navigateur)" >> "$REPORT" ;;
    3) echo "- E2E RUNTIME: SKIP, $(grep '\[e2e\] SKIP' "$E2E_LOG" | tail -1 | cut -c1-140)" >> "$REPORT" ;;
    *) echo "- E2E RUNTIME: ECHEC (loop/logs/e2e-$RUN.log)" >> "$REPORT"
       if [ ! -f loop/tasks/01-45-e2e-repare.md ]; then
         { echo "# Carte, reparer le gate runtime (des ecrans meurent au navigateur)"
           echo
           echo "USE CASE:"
           echo "L'app doit etre UTILISABLE: chaque ecran charge du contenu reel sans erreur"
           echo "console. Le gate runtime (Playwright) vient d'echouer, la preuve est ci-dessous."
           echo
           echo "CONTEXT:"
           echo '~~~'
           grep -vE '^\s*$' "$E2E_LOG" | tail -40 | cut -c1-200
           echo '~~~'
           echo "Lance toi-meme: bash loop/e2e.sh (SKIP=3 si infra absente, repare alors autrement:"
           echo "le defaut est peut-etre un appel API mort, une route cassee, un ecran vide)."
           echo
           echo "DONE WHEN:"
           echo "- bash loop/e2e.sh sort en 0."
           echo
           echo "SCOPE: full"
           echo "PROBE: bash loop/e2e.sh"
         } > loop/tasks/01-45-e2e-repare.md
         cp loop/tasks/01-45-e2e-repare.md loop/state/queue/ 2>/dev/null
         git add loop/tasks/01-45-e2e-repare.md >/dev/null 2>&1
         git commit -qm "loop: gate runtime en echec, carte de reparation en tete de file [loop]" >/dev/null 2>&1 || true
         notify_phone "🔴 Gate runtime (e2e) en ECHEC: carte 01-45 en tete de la prochaine file, preuve dans loop/logs/e2e-$RUN.log"
       fi ;;
  esac
  echo "[loop] e2e rc=$E2E_RC"
fi

bash loop/distill.sh "$REPORT" 2>&1 | sed 's/^/[distill] /' | grep -v '^\[distill\] \[distill\]' || true

# v6.53 PONT MAKER -> MEMOIRE HERMES (demande proprietaire: faire tourner Opus ici et
# injecter l'appris dans la memoire built-in de Hermes). La memoire de Hermes est un
# fichier ($PROFILE/memories/MEMORY.md, toujours active); on y VERSE les verts et lecons
# du run, dedup, quel que soit le maker (Opus, codex, fable). Une future nuit LOCALE
# (qwen via hermes) demarre alors avec ce que les modeles premium ont appris. Decouplage
# total bâtisseur / magasin de memoire.
memory_bridge(){
  local mf="${LOOP_PROFILE_DIR:-$HOME/.hermes-loop-cdc}/memories/MEMORY.md" line
  [ -n "$mf" ] || return 0; mkdir -p "$(dirname "$mf")"
  [ -f "$mf" ] || printf '# MEMORY\n\n## Faits de domaine (loop)\n' > "$mf"
  { [ -d "$mf" ] && return 0; } 2>/dev/null
  printf '\n## Run %s (maker %s)\n' "$RUN" "${LOOP_MAKER:-$DEFAULT_MAKER}" >> "$mf"
  # les verts du run = des capacites acquises
  grep -E '^- .*GREEN' "$REPORT" 2>/dev/null | sed -E 's/^- ([^:]+):.*/- acquis: \1 construit et verifie/' | sort -u | while IFS= read -r line; do
    grep -qF -- "$line" "$mf" 2>/dev/null || printf '%s\n' "$line" >> "$mf"
  done
  # v6.63: les VRAIES lecons du run. L'ancien glob visait loop/proposals/*/lesson-*.md,
  # un fichier que le distiller n'a JAMAIS emis (il ecrit distiller-raw-*.txt, card-rewrite-*.md,
  # hints.d): la branche etait morte, seuls les verts atteignaient hermes. On puise desormais
  # dans les sources reelles: les hints.d distilles (generalisations failure-class -> conseil)
  # et les sections ## LESSONS accumulees sur les cartes (findings de reviewer a corriger).
  for hz in loop/hints.d/*; do
    [ -f "$hz" ] || continue
    # format .hint: 'MATCH: <regex>' puis '---' puis le texte du conseil. On prend le texte
    # (apres ---), condense en une ligne, prefixe par le nom du hint. Dedup par nom.
    local hn htxt; hn="$(basename "$hz" | sed 's/\.[^.]*$//')"
    htxt="$(sed -n '/^---/,$p' "$hz" 2>/dev/null | grep -v '^---' | tr '\n' ' ' | sed 's/  */ /g;s/^ //' | cut -c1-220)"
    [ -n "$htxt" ] || continue
    grep -qF -- "hint $hn:" "$mf" 2>/dev/null || printf -- '- hint %s: %s\n' "$hn" "$htxt" >> "$mf"
  done
  grep -l '## LESSONS' loop/tasks/*.md 2>/dev/null | head -8 | while IFS= read -r lc; do
    sed -n '/## LESSONS/,$p' "$lc" 2>/dev/null | grep -E '^- ' | head -4 | while IFS= read -r line; do
      grep -qF -- "$line" "$mf" 2>/dev/null || printf -- '- lecon (%s): %s\n' "$(basename "$lc" .md)" "${line#- }" >> "$mf"
    done
  done
  echo "[loop] memoire hermes irriguee: $mf ($(grep -c '^- ' "$mf" 2>/dev/null) entrees)"
}
memory_bridge 2>/dev/null || true

# v6.50 LE CRITIQUE PRODUIT (oeil produit), une passe a la fermeture: rend l'app, la juge
# contre les maquettes via un modele vision, seme des cartes d'amelioration. Skip-gracieux
# (comme le conseil sans chair): pas de front/playwright/modele-vision => ne fait rien, ne
# coute aucun green (il tourne APRES le dernier lot). Debrayable par LOOP_CRITIC=0.
if [ "${LOOP_CRITIC:-1}" = 1 ]; then
  echo "[loop] critique produit (passe de fermeture)"
  bash loop/critic.sh "$WT" 2>&1 | sed 's/^/[critic] /' || true
fi

# v6.6: conseil PERIODIQUE d'architecture (1 run sur 5), pas seulement sur echec.
# Anti-derive: des centaines de cycles verts peuvent quand meme accumuler de la dette.
RUNS_N="$(grep -c '	' loop/reports/metrics.tsv 2>/dev/null || echo 0)"
if [ "${RUNS_N:-0}" -gt 1 ] && [ $(( RUNS_N % 5 )) -eq 0 ]; then
  _AF="/tmp/arch-review-$RUN.txt"
  { echo "Revue d'architecture PERIODIQUE, aucun echec declencheur."
    echo "Question au conseil: derive architecturale, dette accumulee, incoherences entre modules, ecarts au cahier des charges. Rends DECISION et au plus UNE DIRECTIVE."
    echo; echo "Delta recent:"; git log --oneline -15; echo; git diff --stat HEAD~15 2>/dev/null | tail -15; } > "$_AF"
  echo "[loop] conseil periodique (run $RUNS_N)"
  bash loop/council.sh "arch-$RUN" "$_AF" 2>&1 | sed 's/^/[council] /' || true
  echo "- CONSEIL PERIODIQUE convoque (run $RUNS_N)" >> "$REPORT"
fi
{ echo; echo "## Learning (v5.9)"; tail -3 loop/reports/metrics.tsv 2>/dev/null | sed 's/^/    /'
  ls "loop/proposals/$(date +%Y%m%d)/" 2>/dev/null | head -6 | sed 's/^/    proposal: /'; } >> "$REPORT"
# v6.47 REQ6 (pilote: 24 lignes d'echec de la meme carte a compter a la main): le
# rapport agrege les echecs repetes par carte (prefixes zz-* fusionnes) en UNE ligne.
_AGG="$(grep -E '^- .*(HARD-FAIL|REDCOMPILE|CODEX-BLOCKED|PROBE-FAILED|FAILED after escalation|no-change)' "$REPORT" 2>/dev/null \
  | sed -E 's/^- ([^:]+):.*/\1/; s/^(zz-[EDH]-)+//' | sort | uniq -c | sort -rn \
  | awk '$1>=3{printf "  - %s: %d echecs cumules\n", $2, $1}')"
if [ -n "$_AGG" ]; then
  { echo; echo "## Echecs agreges (>=3, toutes formes de la meme carte fusionnees)"; printf '%s\n' "$_AGG"; } >> "$REPORT"
fi
# v6.46 point 6 (cahier pilote): un run a 0 vert avec du rouge N'A PAS LE DROIT de
# finir sans une ligne de cause probable. L'autopsie lit les signatures des logs de
# cycle et l'ecrit dans le rapport ET le Telegram (3 autopsies manuelles cette semaine).
if [ "${green_c:-0}" -eq 0 ] && [ $(( ${red_c:-0} + ${hard_c:-0} + ${blocked_c:-0} )) -gt 0 ]; then
  _AUT="$(autopsy)"
  echo "[loop] AUTOPSIE: $_AUT"
  echo "- AUTOPSIE (0 vert): $_AUT" >> "$REPORT"
  notify_phone "🔎 Run a 0 vert ($(basename "$MAIN")). AUTOPSIE: $_AUT"
fi
echo "[loop] done. green=$green_c red=$red_c blocked=$blocked_c skipped=$skip_c hard=$hard_c"
echo "[loop] report: $WT/$REPORT"
osascript -e "display notification \"green=$green_c red=$red_c blocked=$blocked_c skipped=$skip_c\" with title \"Loop terminé\" subtitle \"CDC Crédit Corporate\"" 2>/dev/null || true
# v6.21: digest matin consolide (remplace le ping brut); fallback notify si le digest echoue
bash loop/morning-digest.sh "$WT" 2>/dev/null || \
  notify_phone "✅ Loop done ($RUN). green=$green_c red=$red_c blocked=$blocked_c skipped=$skip_c hard=$hard_c."

OBS="${LOOP_OBSIDIAN:-$HOME/Documents/Obsidian Vault/Projects/CDC Crédit Corporate}"
if [ -d "$OBS" ]; then
  OJ="$OBS/Loop Journal.md"
  [ -f "$OJ" ] || printf '# Loop Journal\n\n' > "$OJ"
  { echo; echo "## Run $RUN, $(date '+%Y-%m-%d %H:%M')"
    echo "- verts: $green_c, rouges: $red_c, bloqués: $blocked_c, sautés: $skip_c, hard: $hard_c (cycles: $cyc)"
    grep -E '^- .*GREEN' "$REPORT" | sed 's/^- /- ✅ /' | head -12
    grep -E '^- .*(CODEX-BLOCKED|FAILED after escalation|PROBE-FAILED|REDCOMPILE)' "$REPORT" | sed 's/^- /- ❌ /' | head -8
    echo "- rapport: $WT/$REPORT"; } >> "$OJ"
  echo "[loop] journal Obsidian mis à jour"
fi
