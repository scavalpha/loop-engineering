#!/usr/bin/env bash
# Run ONE task card. v5.6: single invoke_maker(), fail-closed checker verdict,
# content-hashed lite.ok marker, fast-RED on unrecovered compile errors.
# Writes loop/state/verdict.last (PASS|FAIL|REDCOMPILE|none) for the driver.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$ROOT/loop/stack.sh" ] && . "$ROOT/loop/stack.sh" 2>/dev/null
export PATH="$HOME/.local/bin:$PATH"
CARD="${1:?usage: run-cycle.sh <path-to-task-card.md>}"
# contrat stack (portabilite, adopte du loop pilote): defauts generiques, stack.sh surcharge.
# v6.43: forme :- OBLIGATOIRE, stack.sh est source ligne 7 AVANT ces defauts; la forme
# dure ecrasait le contrat (invisible sur le projet d'origine, valeurs identiques; mine sur tout portage).
BACK_DIR="${BACK_DIR:-backend}"; FRONT_DIR="${FRONT_DIR:-frontend}"   # stack-default
PSLUG_RC="$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
# v6.14: le DOMAINE du projet vient du contrat (panne pilote: constitution semee
# disait le domaine d'UN AUTRE projet a un maker qui en construit un autre)
PROJECT_DOMAIN="${PROJECT_DOMAIN:-a web application}"
constitution(){
  # v6.27: loi universelle dans constitution.md, brief stack (dirs/DB/creds/idiomes) depuis
  # le contrat (STACK_BRIEF). Fin du whack-a-mole: aucun nom propre projet dans
  # constitution.md, tous dans stack.sh. python: substitution simple, multiligne-safe.
  STACK_BRIEF="${STACK_BRIEF:-}" PROJECT_DOMAIN="$PROJECT_DOMAIN" FRONT_DIR="$FRONT_DIR" BACK_DIR="$BACK_DIR" \
  python3 -c 'import os,sys
t=open(sys.argv[1]).read()
for k in ("PROJECT_DOMAIN","FRONT_DIR","BACK_DIR","STACK_BRIEF"):
    t=t.replace("{{"+k+"}}", os.environ.get(k,""))
sys.stdout.write(t)' "$ROOT/loop/constitution.md"
}
CARD_ABS="$(cd "$(dirname "$CARD")" 2>/dev/null && pwd)/$(basename "$CARD")"
MAKER="${LOOP_MAKER:-qwen3-coder:30b}"
MAKER_PATH="$ROOT/loop/shims:$PATH"   # hard-law shims for every maker session
_MVND="$HOME/.sdkman/candidates/mvnd/current/bin/mvnd"                      # stack-default
MVN="${LOOP_MVN:-$([ -x "$_MVND" ] && echo "$_MVND" || echo ./mvnw)}"       # stack-default
# v6.43 contrat v2: les commandes de gate viennent du stack, defauts = historique exact.
GATE_FRONT_CMD="${GATE_FRONT_CMD:-npx ng build}"                            # stack-default
GATE_BACK_CMD="${GATE_BACK_CMD:-$MVN -q test-compile}"                      # stack-default
TOOLCHAIN_HINT="${TOOLCHAIN_HINT:-mvnd/mvnw with the installed JDK, npx ng}" # stack-default
# env outillage des sessions maker/checker: fonction contractuelle, defaut = JDK sdkman
type stack_maker_env >/dev/null 2>&1 || stack_maker_env(){                  # stack-default
  local J="$HOME/.sdkman/candidates/java/current"                          # stack-default
  [ -d "$J" ] && export JAVA_HOME="$J"
  return 0
}
stack_maker_env
mkdir -p "$ROOT/loop/logs" "$ROOT/loop/state"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$ROOT/loop/logs/cycle-$STAMP-$(basename "$CARD" .md).log"
VERDICT_FILE="$ROOT/loop/state/verdict.last"
echo "none" > "$VERDICT_FILE"
rm -f "$ROOT/loop/state/lite.ok"

# content hash of the working change (files listed AND their contents), so a stale
# marker can never let verify skip a build on a tree that changed since (review OV-3/#3).
# includes untracked NEW-file content (git diff HEAD misses it, and new files are the
# maker's dominant output — caught by the harness test suite).
tree_hash(){
  { git status --porcelain 2>/dev/null
    git diff HEAD 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f; do printf '>>%s\n' "$f"; cat "$f" 2>/dev/null; done
  } | shasum -a 256 | cut -d' ' -f1
}

# v5.7.11 fix B: MECHANICAL route-wiring. Route registration is surgical and fumble-prone
# (the maker kept DELETING sibling routes while editing app.routes.ts). So the maker only
# creates the component; the HARNESS inserts the route deterministically, preserving every
# existing route. Card carries: ROUTE: <path> | <importPath> | <ComponentClass> | <title>.
# Idempotent (skips if the path already exists), so it is safe to run after every maker call.
wire_route(){
  local rl; rl="$(grep -m1 '^ROUTE:' "$CARD" 2>/dev/null | sed 's/^ROUTE:[[:space:]]*//')"
  [ -z "$rl" ] && return 0
  local routes="$ROOT/$FRONT_DIR/src/app/app.routes.ts"
  [ -f "$routes" ] || return 0
  ROUTE_SPEC="$rl" python3 - "$routes" <<'PY'
import os, re, sys
parts = [x.strip() for x in os.environ["ROUTE_SPEC"].split("|")]
if len(parts) < 3: sys.exit(0)
path, imp, cls = parts[0], parts[1], parts[2]
title = parts[3] if len(parts) > 3 else cls
f = sys.argv[1]; src = open(f).read()
if re.search(r"path:\s*'%s'" % re.escape(path), src):
    print("[wire-route] '%s' already present" % path); sys.exit(0)
block = ("      {\n        path: '%s',\n        loadComponent: () =>\n"
         "          import('%s').then((m) => m.%s),\n        title: '%s',\n      },\n"
         ) % (path, imp, cls, title)
m = re.search(r"\n(\s*)\{\s*path:\s*'',\s*redirectTo:", src)
if not m:
    print("[wire-route] no redirect anchor; not wired"); sys.exit(1)
i = m.start() + 1
open(f, "w").write(src[:i] + block + src[i:])
print("[wire-route] inserted '%s' -> %s" % (path, cls))
PY
}

# v5.7.11: strip maker-created junk anywhere in the worktree. The maker must not self-verify
# or write summaries; it kept dropping hermes-verify-*.ts and verification-summary.md in the
# ROOT (not just src). Remove untracked verify/summary/notes junk tree-wide + any .md inside
# the source trees (source dirs never hold .md). Real code files stay (folder-scope intact).
clean_junk(){
  local d j
  git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null \
    | grep -iE '(^|/)hermes-verify[^/]*|(^|/)[^/]*(implementation_summary|verification-summary|[-_]summary|[-_]notes|scratch|diagnostic)\.(md|txt|ts|js)$|(^|/)verify[^/_-]*[_-][^/]*\.(sh|mjs|cjs|java|class|ts|py)$|\.class$' \
    | while IFS= read -r j; do rm -f "$ROOT/$j" && echo "[clean-junk] removed junk $j"; done
  for d in "$FRONT_DIR/src" "$BACK_DIR/src"; do
    [ -d "$ROOT/$d" ] || continue
    git -C "$ROOT" ls-files --others --exclude-standard "$d" 2>/dev/null | grep -iE '\.md$' | while IFS= read -r j; do
      rm -f "$ROOT/$j" && echo "[clean-junk] removed junk $j"
    done
  done
  # v5.7.9: the self-compile maker sometimes cd's into a module then writes a module-relative
  # path, producing a DOUBLED prefix (frontend/frontend/...). The
  # build ignores it (outside its src tree) so nothing catches it. Strip untracked files under
  # a doubled project-dir prefix before the gate commits, then prune the empty doubled dirs.
  # v5.9.8: RESTORE doubled-path files, do not blindly delete. The maker sometimes cd's
  # into a module and recreates the module dir inside itself; it may MOVE real code there,
  # making the doubled copy the ONLY copy. The old rm -rf destroyed 40 real files on card
  # 25 (the checker caught it; the harness was the vandal). Now: a doubled file goes BACK
  # to its correct path when that path is missing; only true duplicates are removed.
  for mod in "$FRONT_DIR" "$BACK_DIR"; do
    git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null | grep -E "^$mod/$mod/" \
      | while IFS= read -r j; do
          correct="${j/#$mod\/$mod\//$mod/}"
          if [ ! -f "$ROOT/$correct" ]; then
            mkdir -p "$ROOT/$(dirname "$correct")"
            mv "$ROOT/$j" "$ROOT/$correct" && echo "[clean-junk] restored doubled-path $j to $correct"
          else
            rm -f "$ROOT/$j" && echo "[clean-junk] removed duplicate doubled-path $j"
          fi
        done
    find "$ROOT/$mod/$mod" -type d -empty -delete 2>/dev/null
    rmdir "$ROOT/$mod/$mod" 2>/dev/null
  done
  # v5.7.9: the self-compile maker's build tooling emits Eclipse IDE files (.classpath,
  # .project, .factorypath, .settings/). Never source, remove untracked ones before commit.
  git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null \
    | grep -E '(^|/)\.(classpath|project|factorypath)$|(^|/)\.settings/' \
    | while IFS= read -r j; do rm -f "$ROOT/$j" && echo "[clean-junk] removed IDE file $j"; done
}

# single maker call site (DRY, review #4): shims + toolset + model + timeout + logging.
# LOOP_SANDBOX=1 gives the maker a FULL terminal (read sibling repos, read-only git, grep
# the disk with free local tokens) fenced by sandbox-exec: read anywhere, write only in the
# worktree, no external network. OS-enforced, so shims become belt-and-suspenders. Without
# the flag, the maker keeps the file-only toolset (no shell) and the old behaviour.
# After every maker call: wire the card's route (mechanical) and strip junk (both idempotent).
# v5.9.1 progress watchdog: kill on STALL, not on clock. A maker actively producing
# (session log growing, or files changing) gets to keep working up to the hard ceiling;
# one that stalls (no output AND no file changes across 2 consecutive 10-min checks) is
# killed early. Replaces the fixed `timeout` that killed 9/17 sessions MID-WORK at 30m.
# Returns 124 on watchdog kill so the driver's restart path still triggers (which, as of
# v5.9.1, CONTINUES from the partial work instead of wiping it).
# Progress = ANY of: session log grew (tool calls, flushes), tree changed (file writes),
# the maker process tree burned CPU (builds, greps, DB reads), or the ollama runner burned
# CPU (the model is THINKING: long analysis/generation phases write nothing and hermes
# buffers its log, so CPU burn is the only honest signal there). Stall = ALL of them flat
# across 2 consecutive windows = a genuinely dead session, not a slow-thinking one.
cpu_burn(){ # $1=maker pid -> total cputime seconds of maker tree + ollama runner
  local total=0 p t
  for p in "$1" $(pgrep -P "$1" 2>/dev/null) $(pgrep -f 'ollama.*runner|ollama_llama' 2>/dev/null | head -3); do
    t="$(ps -o cputime= -p "$p" 2>/dev/null | tr -d ' ')"
    [ -n "$t" ] && total=$(( total + $(echo "$t" | awk -F'[:.]' '{if (NF>=3) print $1*3600+$2*60+$3; else print $1*60+$2}') ))
  done
  echo "$total"
}
watchdog_wait(){ # $1=pid  $2=hard_cap_secs
  local pid="$1" cap="$2" iv="${LOOP_WATCH_INTERVAL:-600}" waited=0 since=0 stall=0 sig last=""
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1; waited=$(( waited + 1 )); since=$(( since + 1 ))
    if [ "$waited" -ge "$cap" ]; then
      echo "[watchdog] hard ceiling ${cap}s reached, killing maker (work preserved)" >>"$LOG"
      kill "$pid" 2>/dev/null; sleep 3; kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 124
    fi
    [ "$since" -lt "$iv" ] && continue
    since=0
    sig="$(stat -f %z "$LOG" 2>/dev/null || echo 0)-$(tree_hash)-$(cpu_burn "$pid")"
    if [ "$sig" = "$last" ]; then stall=$(( stall + 1 )); else stall=0; fi
    last="$sig"
    if [ "$stall" -ge 2 ]; then
      echo "[watchdog] STALLED (no output, no file changes, no CPU burn across 2x${iv}s), killing maker" >>"$LOG"
      kill "$pid" 2>/dev/null; sleep 3; kill -9 "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; return 124
    fi
  done
  wait "$pid" 2>/dev/null
}

# v6.16: kind EFFECTIF par carte. LOOP_MAKER_KIND est global, mais le MODELE change a
# l'escalade (ESCALATED: claude-opus-4-8 sous un run codex). Si le nom du modele designe
# une famille frontier connue, elle prime: la FAMILLE bascule, pas seulement le modele.
# Sinon (modele local, ou placeholder), on garde le kind global du run.
maker_kind_for(){ # $1=modele
  case "$1" in
    claude-*|*opus*|*sonnet*|*haiku*) echo claude ;;
    codex|gpt-*|o1-*|o3-*|o4-*)        echo codex ;;
    *) echo "${LOOP_MAKER_KIND:-hermes}" ;;
  esac
}

invoke_maker(){ # $1=prompt  $2=hard_cap_secs
  local rc TOOLSETS HHOME HPID EKIND
  EKIND="$(maker_kind_for "$MAKER")"
  # The maker gets a terminal so it can build/test/fix its own work before review.
  # Safety net for that freedom: worktree isolation (the main checkout is never touched) +
  # the gate's atomic commit/revert (a bad change is reverted whole) + the v5.9 loop
  # profile's write-boundary hook (blocks file-tool writes outside the worktree).
  # LOOP_HERMES_HOME (set by the driver after the profile smoke passes) routes the maker
  # through the LOOP-SCOPED Hermes profile: N2 hook + N4 fallback + N6 scoped memory.
  # LOOP_MEMORY_TRIAL=1 (default) adds the memory toolset for the N6 measurement.
  # LOOP_SANDBOX=1 additionally wraps in the OS sandbox (opt-in; hangs on full runs).
  TOOLSETS="${LOOP_TOOLSETS:-file,terminal}"
  [ "${LOOP_MEMORY_TRIAL:-1}" = 1 ] && [ -n "${LOOP_HERMES_HOME:-}" ] && case "$TOOLSETS" in
    *memory*) : ;; *) TOOLSETS="$TOOLSETS,memory" ;; esac
  HHOME="${LOOP_HERMES_HOME:-$HOME/.hermes}"
  if [ "$EKIND" = "stub" ]; then
    # v6.46 P1 (cahier des charges pilote): maker STUB, exclusivement pour le smoke de
    # release (execution REELLE du chemin semis->carte->maker->gate->probe sur un projet
    # jouet, sans LLM ni quota). Jamais en production: exige LOOP_MAKER_STUB explicite.
    env LOOP_REPO_ROOT="$ROOT" LOOP_CARD="$CARD_ABS" bash "${LOOP_MAKER_STUB:?stub exige LOOP_MAKER_STUB}" >>"$LOG" 2>&1 &
  elif [ "${LOOP_SANDBOX:-0}" = 1 ] && command -v sandbox-exec >/dev/null 2>&1; then
    sandbox-exec \
      -D WT="$ROOT" -D HH="$HHOME" -D CACHE="$HOME/Library/Caches" -D DOTCACHE="$HOME/.cache" \
      -f "$ROOT/loop/sandbox/maker.sb" \
      env PATH="$MAKER_PATH" LOOP_REPO_ROOT="$ROOT" LOOP_CARD="$CARD_ABS" ${LOOP_HERMES_HOME:+HERMES_HOME="$LOOP_HERMES_HOME"} \
        hermes -m "$MAKER" -t "$TOOLSETS" -z "$1" --cli >>"$LOG" 2>&1 &
  elif [ "$EKIND" = "claude" ]; then
    # v6.11: maker FRONTIER claude (Opus). Print mode non interactif; bypassPermissions
    # car le maker DOIT compiler et tester lui-meme (doctrine self-compile). Filets: le
    # worktree isole, le garde d'integrite, le gate atomique commit/revert. Juge = codex
    # (autre famille): l'independance juge/maker est meilleure qu'en local.
    env -i HOME="$HOME" USER="$USER" TERM=xterm PATH="$MAKER_PATH" \
      LOOP_REPO_ROOT="$ROOT" LOOP_CARD="$CARD_ABS" \
      claude --model "${LOOP_MAKER:-claude-opus-4-8}" --effort "${LOOP_CLAUDE_EFFORT:-medium}" -p "$1" --permission-mode bypassPermissions --setting-sources=project --strict-mcp-config >>"$LOG" 2>&1 &
      # v6.50.1/.3 ISOLATION DURE de la session maker claude (2 hangs distincts attrapes
      # en run premium 10/07, chacun tuant une carte). (1) --setting-sources=project: sans
      # lui la session herite des PLUGINS UTILISATEUR de ~/.claude (superpowers, caveman,
      # hooks): le hook SessionEnd a pendu 10min APRES le 'Done', rc=143, 26min de travail
      # Opus FINI et VERT reverte. (2) --strict-mcp-config (sans --mcp-config = ZERO serveur
      # MCP): sinon la session tente de demarrer les MCP de l'operateur (obsidian qui exige
      # l'app, context7 qui se deconnecte...) et PEND au demarrage avant meme d'ecrire son
      # premier event (cycles 3-4: session jamais nee). Un maker de CODE n'a besoin que de
      # file+bash dans le worktree: zero plugin, zero MCP, zero hook personnel.
  elif [ "$EKIND" = "codex" ]; then
    # v6.10: maker FRONTIER (projet secondaire pendant que le GPU local est pris).
    # codex exec: sandbox workspace-write = frontiere d'ecriture native (equivalent du
    # hook hermes), abonnement flat (pas de facturation token). Perdus en mode codex:
    # pre_verify, memoire, fallback local; le gate et les probes restent la loi.
    # v6.50 (routing par role, benchmark 16 cellules pilote): LOOP_MAKER_MODEL choisit
    # le modele codex (-m, ex gpt-5.6-terra, champion debit) et LOOP_MAKER_EFFORT le
    # raisonnement (defaut medium: au-dela de high = anti-efficient, mesure). RIEN en dur:
    # sans LOOP_MAKER_MODEL, codex garde son modele par defaut (comportement historique).
    env PATH="$MAKER_PATH" LOOP_REPO_ROOT="$ROOT" LOOP_CARD="$CARD_ABS" \
      codex exec --sandbox workspace-write --skip-git-repo-check \
      ${LOOP_MAKER_MODEL:+-m "$LOOP_MAKER_MODEL"} \
      ${LOOP_MAKER_EFFORT:+-c model_reasoning_effort="$LOOP_MAKER_EFFORT"} \
      -C "$ROOT" "$1" >>"$LOG" 2>&1 &
  else
    env PATH="$MAKER_PATH" LOOP_REPO_ROOT="$ROOT" LOOP_CARD="$CARD_ABS" ${LOOP_HERMES_HOME:+HERMES_HOME="$LOOP_HERMES_HOME"} \
      hermes -m "$MAKER" -t "$TOOLSETS" -z "$1" --cli >>"$LOG" 2>&1 &
  fi
  HPID=$!
  watchdog_wait "$HPID" "$2"; rc=$?
  wire_route >>"$LOG" 2>&1
  clean_junk >>"$LOG" 2>&1
  return $rc
}

# --- skills injection (general tier + project tier) ---
GENERAL_SKILLS="${LOOP_GENERAL_SKILLS:-$HOME/dev/loop-skills-general}"
SK_CONTENT=""
# v6.2 prompt diet: skills grow via the distiller, cap each tier so prefill cost cannot
# creep (8KB general + 6KB project; oldest content wins within a file, files sorted).
if ls "$GENERAL_SKILLS"/*.md >/dev/null 2>&1; then SK_CONTENT="$(cat "$GENERAL_SKILLS"/*.md | head -c 8000)"; fi
# v6.9 C2: store global (universel + stack courant), la connaissance croisee des loops
# v6.45.1 BUG C (pilote, 9 faux REDCOMPILE): le RE-SOURCE de stack.sh qui vivait ici
# re-clobberait GATE_BACK_CMD='' PAR-DESSUS le defaut applique en tete -> bash -c
# "cd ... && " -> syntax error -> compile sans classpath -> cascade de fausses erreurs
# sur toutes les cartes. stack.sh se source UNE fois (ligne 7), jamais en aval des
# defauts. STACK_NAME garde un defaut :- (il vient du source de la ligne 7).
STACK_NAME="${STACK_NAME:-angular-spring}"
_GSTORE="${LOOP_SKILLS_STORE:-$HOME/dev/loop-skills-general}"
for _gd in "$_GSTORE/universel" "$_GSTORE/stack-$STACK_NAME"; do
  if ls "$_gd"/*.md >/dev/null 2>&1; then SK_CONTENT="$SK_CONTENT
$(cat "$_gd"/*.md 2>/dev/null | head -c 3000)"; fi
done
if ls "$ROOT"/loop/skills/*.md >/dev/null 2>&1; then SK_CONTENT="$SK_CONTENT
$(cat "$ROOT"/loop/skills/*.md 2>/dev/null | grep -v '^- 20[0-9-]*: ' | head -c 6000)"; fi
# v6.50 (pilote: adopter la taste-skill, PREVENTIF cote maker). Skills de tier FRONT,
# injectes UNIQUEMENT pour les cartes scope=front (regles anti-slop de design). Curation
# maison, pas le depot externe brut (supply chain: ce texte entre dans le prompt maker).
# Le design system du projet (DESIGN-stitch.md) reste autoritaire, ces regles sont des
# garde-fous generiques qui ne priment jamais sur l'identite du projet.
if [ "${VERIFY_SCOPE:-full}" = "front" ] && ls "$ROOT"/loop/skills-front/*.md >/dev/null 2>&1; then
  SK_CONTENT="$SK_CONTENT
$(cat "$ROOT"/loop/skills-front/*.md 2>/dev/null | head -c 4000)"
fi
SKILLS=""
[ -n "$SK_CONTENT" ] && SKILLS="

########################################################################
## PROVEN PATTERNS (general engineering + this project, follow them)
########################################################################
$(printf '%s' "$SK_CONTENT" | head -c 7000)"

# v5.7.4: inject the CURRENT content of every MODIFY file. The maker cannot preserve
# what it never sees, and Hermes throttles re-reads (this is what sank card 02b: it
# deleted existing routes, then hit a read limit trying to restore them). With the
# content in the prompt, no read is needed and there is nothing to lose.
build_modify_ctx(){
  local mods mf out=""
  mods="$(awk '/FILES \(modify\)/{f=1;next} /^(FILES|SPEC|SCOPE|PROBE|GOAL|DEPENDS|ACCEPTANCE|MAKER|ESCALATED|##)/{f=0} f&&/^- /{print $2}' "$CARD" 2>/dev/null)"
  for mf in $mods; do
    [ -f "$ROOT/$mf" ] || continue
    local body
    body="$(git -C "$ROOT" show "HEAD:$mf" 2>/dev/null)"; [ -z "$body" ] && body="$(cat "$ROOT/$mf" 2>/dev/null)"
    out="$out

### ORIGINAL content of $mf (this is the committed baseline to PRESERVE)
Output the COMPLETE file keeping EVERY line below, adding ONLY the card's change. NEVER delete existing code, routes, imports, or methods.
\`\`\`
$(printf '%s' "$body" | head -c 4000)
\`\`\`"
  done
  [ -n "$out" ] && printf '%s' "
########################################################################
## FILES YOU MUST MODIFY, their CURRENT content follows (preserve it all)
########################################################################$out"
}
MODIFY_CTX="$(build_modify_ctx)"

# v6.50 (pilote #1 defect: front makers INVENT DTO field names instead of reading the
# real controller, so every field renders undefined and the e2e mock is shaped to the
# wrong model -> green while the live contract is broken). For a scope=front card that
# calls /api/*, paste the REAL backend contract (endpoint signatures + response DTO/View
# records) into the maker prompt. Best-effort, stack-agnostic: finds nothing off-Java =>
# empty, the constitution rule still stands. The maker has the repo; this makes it look.
build_api_ctx(){
  [ "${VERIFY_SCOPE:-full}" = "front" ] || return 0
  [ -n "${BACK_DIR:-}" ] && [ -d "$ROOT/$BACK_DIR" ] || return 0
  command -v rg >/dev/null 2>&1 || return 0
  local paths p f hits out="" d df dtos
  paths="$(grep -oE '/api/[a-zA-Z0-9_{}/-]+' "$CARD" 2>/dev/null | sed -E 's/\{[^}]*\}//g; s#/+#/#g; s#/$##' | sort -u | head -8)"
  [ -n "$paths" ] || return 0
  for p in $paths; do
    hits="$(rg -l --no-messages -F "$p" "$ROOT/$BACK_DIR" 2>/dev/null | grep -iE 'controller' | head -2)"
    for f in $hits; do
      out="$out
### endpoint $p  ($(basename "$f"))
$(rg --no-messages -n -B1 -A2 -F "$p" "$f" 2>/dev/null | head -10)"
    done
  done
  dtos="$(rg --no-messages -oE '\b[A-Z][A-Za-z0-9]*(Response|View|Dto|DTO)\b' "$ROOT/$BACK_DIR" 2>/dev/null | sort -u | head -12)"
  for d in $dtos; do
    df="$(rg -l --no-messages "(record|class|interface)[[:space:]]+$d\b" "$ROOT/$BACK_DIR" 2>/dev/null | head -1)"
    [ -n "$df" ] || continue
    out="$out
### DTO $d ($(basename "$df"))
$(rg --no-messages -n -A6 "(record|class|interface)[[:space:]]+$d\b" "$df" 2>/dev/null | head -9)"
  done
  [ -n "$out" ] && printf '%s' "

########################################################################
## REAL BACKEND CONTRACT for the endpoints this card calls
########################################################################
Match these EXACT field names and enum values in your front model and template.
Shape your test mock to THIS backend contract, NEVER to an invented front model.
Inventing DTO field names is the #1 defect: fields render undefined, the mock is
shaped to the wrong model, and the e2e passes green while the live UI is broken.$out"
}
API_CTX="$(build_api_ctx)"

# v5.9.1/.4: previous failed attempt (banked by the driver before revert) + WHY it was
# rejected. The maker applies its own old work and fixes the exact lines, "maybe a single
# line out of 10000 made it fail", instead of rebuilding from zero.
PREV_WIP=""
if [ -s "$ROOT/loop/state/wip-current.patch" ]; then
  WIP_WHY=""
  [ -s "$ROOT/loop/state/wip-current.findings" ] && WIP_WHY="

## WHY IT WAS REJECTED (the reviewer's findings / compile errors, verbatim)
$(head -c 4000 "$ROOT/loop/state/wip-current.findings")"
  PREV_WIP="

########################################################################
## YOUR PREVIOUS ATTEMPT EXISTS, do not start from scratch
########################################################################
A prior session already built this card; the gate rejected it and reverted the tree. The
FULL diff of that attempt is saved at loop/state/wip-current.patch (also previewed below).
Recommended path:
1. Run: git apply loop/state/wip-current.patch   (allowed; restores your previous work)
2. Read the rejection reasons below and fix EXACTLY those points, often a handful of
   lines is all that was wrong.
3. Rebuild and test as usual.
Only rebuild from scratch if the findings say the approach itself was fundamentally wrong.
$WIP_WHY

## PATCH PREVIEW (first 6KB; the full patch is at loop/state/wip-current.patch)
$(head -c 6000 "$ROOT/loop/state/wip-current.patch")"
fi

PROMPT="$(constitution)$SKILLS$MODIFY_CTX$API_CTX$PREV_WIP

########################################################################
## YOUR TASK CARD, this session's only job
########################################################################
$(cat "$CARD")

Execute this card now: reach its GOAL and make every PROBE pass, editing or creating
whatever files across the project folder it takes (the FILES list is a hint, not a limit),
each complete and syntactically correct, preserving existing code you are not changing.
Then BUILD and TEST your work in your terminal, read the errors, fix them, and build again,
iterating until it compiles cleanly and the tests pass. Stay inside the project folder,
EXCEPT if this card is SCOPE: sidecar: then edit the sidecar repo at
its absolute path ${SIDECAR_DIR:-~/dev/sidecar} instead, build and test it there
with its own build tool (see the sidecar brief), and do NOT touch the main front/back for
such a card. Do
NOT stop while a compile error you can see remains. When it builds green, stop."

# v6.74 (faille pilote 17/07: le critic/front-review colle un log d'outil BRUT dans le
# CONTEXT d'une carte; un octet non-UTF-8 (sequence multi-octets coupee par une troncature)
# fait HARD-FAIL `codex exec` = "invalid UTF-8 was detected in one or more arguments", la
# carte re-echoue a chaque run. claude/hermes tolerent, codex non). Ceinture-bretelles: on
# assainit le prompt final en UTF-8 valide juste avant l'envoi, quel que soit le maker
# (iconv -c jette les octets invalides; no-op si deja propre). Defense en profondeur: la
# source (critic/front-review) assainit AUSSI a l'ecriture, ceci couvre toute autre source.
PROMPT="$(printf '%s' "$PROMPT" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null || printf '%s' "$PROMPT")"

cd "$ROOT"
# v5.9.6: a card may declare its own time budget for long work (big analysis, migration):
#   BUDGET: 3h   |   BUDGET: 90m   |   BUDGET: 5400
# The watchdog still kills a genuinely dead session early; the budget only raises the
# hard ceiling for this card. Without BUDGET: the TASK_TIMEOUT default applies.
budget_secs(){ # "3h"|"90m"|"5400" -> seconds, empty if unparseable
  case "$1" in
    *h) printf '%s' "$(( ${1%h} * 3600 ))" 2>/dev/null ;;
    *m) printf '%s' "$(( ${1%m} * 60 ))" 2>/dev/null ;;
    ''|*[!0-9]*) : ;;
    *) printf '%s' "$1" ;;
  esac
}
CARD_BUDGET="$(budget_secs "$(grep -m1 '^BUDGET:' "$CARD" 2>/dev/null | awk '{print $2}')")"
MAKER_CAP="${CARD_BUDGET:-${TASK_TIMEOUT:-3600}}"
[ -n "$CARD_BUDGET" ] && echo "[cycle] card budget: ${CARD_BUDGET}s"
{ echo "########## PROMPT SENT $(date) (maker=$MAKER) ##########"
  printf '%s\n' "$PROMPT"; echo; echo "########## RESPONSE ##########"; } > "$LOG"
# v6.46: kind= est le maker EFFECTIF (codex/claude/hermes/stub). L'etiquette maker= seule
# etait trompeuse: elle affichait le defaut de la variable (qwen3-coder:30b) meme quand
# LOOP_MAKER_KIND=codex routait reellement vers codex (diagnostic pilote fausse).
echo "[cycle] card=$(basename "$CARD") maker=$MAKER kind=$(maker_kind_for "$MAKER") scope=${VERIFY_SCOPE:-full} log=$LOG"
invoke_maker "$PROMPT" "$MAKER_CAP"; rc=$?
echo "[cycle] hermes exit=$rc"
rm -rf "$ROOT/tmp" "$ROOT/Users" "$ROOT/src" 2>/dev/null

# --- compile-repair: bounded, compiler output fed back. Returns 1 if STILL red after
# the final round (fast-RED, review OV-8: don't spend a frontier review on broken code).
compile_repair(){ # $1=rounds
  local rounds="$1" attempt ERRS SCOPE RP
  SCOPE="${VERIFY_SCOPE:-full}"
  for attempt in $(seq 1 "$rounds"); do
    ERRS=""
    # v6.43: commandes contractuelles + garde d'existence des dossiers (api-only sans
    # front: le gate front ne doit pas echouer sur un dossier absent, il n'existe pas).
    if [ "$SCOPE" != "back" ] && [ -d "$ROOT/$FRONT_DIR" ] && ! timeout 420 bash -c "cd '$ROOT/$FRONT_DIR' && $GATE_FRONT_CMD" >/tmp/$PSLUG_RC-lite-front.log 2>&1; then
      ERRS="## FRONT BUILD ERRORS
$(tail -40 /tmp/$PSLUG_RC-lite-front.log)"
    fi
    if [ "$SCOPE" != "front" ] && [ -d "$ROOT/$BACK_DIR" ] && ! timeout 420 bash -c "cd '$ROOT/$BACK_DIR' && $GATE_BACK_CMD" >/tmp/$PSLUG_RC-lite-svc.log 2>&1; then
      ERRS="$ERRS
## BACKEND COMPILE ERRORS
$(grep -E 'ERROR|error:' /tmp/$PSLUG_RC-lite-svc.log | head -30)"
    fi
    if [ -z "$ERRS" ]; then
      echo "[repair] lite check clean"
      tree_hash > "$ROOT/loop/state/lite.ok"
      return 0
    fi
    echo "[repair] compile errors, repair attempt $attempt/$rounds"
    printf -- '- [repair] %s attempt %s (compile errors)\n' "$(basename "$CARD" .md)" "$attempt" >> "$ROOT/loop/state/journal.md"
    # v5.9: hints are DATA (loop/hints.d/*.hint), not code. Each file: "MATCH: <egrep>",
    # a "---" separator, then the hint body appended to the repair prompt when the MATCH
    # hits the compile errors. The distiller may ADD hint files (artifact tier) so the loop
    # learns new repair patterns without touching this script (law tier).
    HINTS=""
    for hf in "$ROOT"/loop/hints.d/*.hint; do
      [ -f "$hf" ] || continue
      hrx="$(sed -n 's/^MATCH:[[:space:]]*//p' "$hf" | head -1)"
      [ -n "$hrx" ] || continue
      if printf '%s' "$ERRS" | grep -qiE "$hrx"; then
        HINTS="$HINTS

$(sed '1,/^---$/d' "$hf")"
      fi
    done
    RP="$(constitution)

########################################################################
## REPAIR TASK
########################################################################
Your previous change for the task card below FAILED to compile. Fix ONLY the
compilation errors listed, smallest possible edits. No new files unless an error
requires one.

## ORIGINAL TASK CARD
$(cat "$CARD")
$MODIFY_CTX

$ERRS
$HINTS

Fix the errors now, then stop."
    { echo; echo "########## COMPILE-REPAIR $attempt $(date) ##########"; printf '%s\n' "$ERRS"; echo; echo "########## REPAIR RESPONSE ##########"; } >> "$LOG"
    invoke_maker "$RP" 900 || true
    rm -rf "$ROOT/tmp" "$ROOT/Users" "$ROOT/src" 2>/dev/null
  done
  return 1   # still red after the final round
}

# --- codex checker: frontier review of the uncommitted change vs the card ---
run_checker(){ # $1=round label. sets CHECKER_OUT, CHECKER_V
  local RVP EFFORT HNOTE
  # If the card is route-wired, the harness (not the maker) edited app.routes.ts. Tell the
  # reviewer that change is expected, else it flags a harness edit as a maker violation and
  # the card can never pass (maker reverts route -> harness re-adds it -> flagged again).
  HNOTE=""
  if grep -q '^ROUTE:' "$CARD" 2>/dev/null; then
    HNOTE="

HARNESS-OWNED CHANGE: the harness itself added this card's ROUTE to
$FRONT_DIR/src/app/app.routes.ts. That app.routes.ts change is EXPECTED and
correct. Do NOT flag it or ask to revert it. Judge ONLY the component/source files the
maker created."
  fi
  RVP="You are a pragmatic senior engineer reviewing UNCOMMITTED changes an AI teammate
made to deliver the card below. Inspect the changes yourself (run git diff, read the new
and modified files, and read neighbouring code for context). Judge only two things:
1. DELIVERY: does it deliver what the card asks, does the described behaviour actually work
   end to end (wired up, reachable, not a stub, not truncated)?
2. SOUNDNESS: is the code correct and consistent with the existing codebase (uses the
   existing patterns and data sources, breaks or deletes nothing that already worked, no
   empty or placeholder files)?
The maker chose its OWN files, structure and imports and MAY add or edit any file it needs.
That freedom is expected: do NOT flag which files it created or touched, how many files, or
which service or pattern it picked, UNLESS that choice makes the card fail, breaks existing
behaviour, or is genuinely unsound. Cosmetic or stylistic preferences are NOT findings.
Report the SMALLEST set of real, blocking findings only. Do NOT modify any file: you may
BUILD and RUN TESTS to verify your judgement (the repo's own toolchain is on your PATH:
$TOOLCHAIN_HINT), but never edit, create, or delete source files;
any tree change you make will be detected and reverted. Never report tooling or
environment problems as findings; if a tool fails for you, judge by reading the code.
A finding is only valid if it stops the card's use case from working or is genuinely
unsound code, AND the maker can fix it by editing THIS repository now (which it always
can: it has the whole project folder). If something the use case needs does not exist yet,
a missing endpoint, service, entity or route that another card would normally build, that
IS a finding, and its suggested fix is BUILD IT: tell the maker to add the minimal working
version itself. Never advise waiting for another card, never call cross-card work out of
scope, and never ask to revert a scope expansion the maker made to reach the goal: a maker
that builds missing prerequisites or refactors neighbouring code toward the goal is doing
correct engineering, not violating anything.
End with exactly 'VERDICT: PASS' or 'VERDICT: FAIL', then list only the blocking findings,
each with a one-line suggested fix.
If the card is genuinely too big to build well in one pass, ALSO add a line starting
'SPLIT-SUGGESTION:'. Advisory, for the human, not auto-applied.

## CARD
$(cat "$CARD")$HNOTE"
  # v6.74: le prompt du checker inclut la carte (CONTEXT possiblement pollue); codex exec
  # HARD-FAIL sur tout octet non-UTF-8. Assainir avant l'envoi (no-op si deja propre).
  RVP="$(printf '%s' "$RVP" | iconv -f UTF-8 -t UTF-8 -c 2>/dev/null || printf '%s' "$RVP")"
  EFFORT=""; [ "${VERIFY_SCOPE:-full}" = "front" ] && EFFORT="-c model_reasoning_effort=low"
  # v5.9.2 (user): the checker gets EXACTLY the maker's toolchain (the machine's real JDK
  # via sdkman + mvnd + node), workspace-write so builds can write target*/dist. Codex's
  # earlier "install a JDK" finding was its own bare spawn env missing JAVA_HOME, not a
  # missing JDK. Verifying-by-running makes it a stronger reviewer than read-only.
  # INTEGRITY GUARD: snapshot the maker's work before review; if the checker mutates ANY
  # source (prompt forbids it, but law > prompt), restore the maker's exact state.
  local JHOME PRE_HASH PRE_PATCH
  # v6.43: env outillage via stack_maker_env (deja appelee au chargement, JAVA_HOME
  # exporte si pertinent); JHOME ne sert que le defaut angular-spring du checker.
  JHOME="${JAVA_HOME:-}"   # stack-default
  PRE_HASH="$(tree_hash)"
  PRE_PATCH="/tmp/cc-prechecker-$$.patch"
  git add -A >/dev/null 2>&1; git diff --cached HEAD > "$PRE_PATCH" 2>/dev/null; git reset -q >/dev/null 2>&1
  CHECKER_OUT="$(timeout 360 env PATH="$MAKER_PATH" ${JHOME:+JAVA_HOME="$JHOME"} \
    codex exec --sandbox workspace-write --skip-git-repo-check $EFFORT "$RVP" 2>/dev/null)"
  if [ "$(tree_hash)" != "$PRE_HASH" ]; then
    echo "[checker] tree mutated during review, restoring maker state" >>"$LOG"
    git reset --hard HEAD >/dev/null 2>&1; git clean -fd -e loop >/dev/null 2>&1
    git apply --whitespace=nowarn "$PRE_PATCH" 2>/dev/null || git apply --3way "$PRE_PATCH" 2>/dev/null || true
  fi
  rm -f "$PRE_PATCH"
  { echo; echo "########## CHECKER (codex, round $1) ##########"; printf '%s\n' "${CHECKER_OUT:-checker unavailable}"; } >> "$LOG"
  CHECKER_V="$(printf '%s' "$CHECKER_OUT" | grep -oiE 'VERDICT: *(PASS|FAIL)' | tail -1)"
  # findings count = the progress gradient. Drives convergence-gating, so it MUST count a
  # finding however Codex formats it: dash/star bullets AND numbered items (1. / 2) ...).
  # Counting only dash-bullets gave a FALSE ZERO when Codex switched to a numbered list,
  # faking "converged to clean" and driving a wasteful re-roll that broke working code.
  CHECKER_F="$(printf '%s' "$CHECKER_OUT" | grep -cE '^[[:space:]]*([-*]|[0-9]+[.)])[[:space:]]')"
  echo "[checker] round $1: ${CHECKER_V:-no verdict} (findings ${CHECKER_F})"
}

if [ "$rc" -eq 0 ] && [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  if ! compile_repair 3; then
    # fast-RED: unrecovered compile errors, skip the expensive checker + verify entirely
    echo "REDCOMPILE" > "$VERDICT_FILE"
    echo "[cycle] fast-RED (compile errors survived repair)"
    printf -- '- [cycle] %s REDCOMPILE (compile errors survived)\n' "$(basename "$CARD" .md)" >> "$ROOT/loop/state/journal.md"
    exit "$rc"
  fi

  # destructive-edit guard (v5.7.4): flag a MODIFY file that lost a lot of content
  # (deterministic catch of the 02b failure class, alongside Codex).
  for mf in $(awk '/FILES \(modify\)/{f=1;next} /^(FILES|SPEC|SCOPE|PROBE|GOAL|DEPENDS|ACCEPTANCE|MAKER|ESCALATED|##)/{f=0} f&&/^- /{print $2}' "$CARD" 2>/dev/null); do
    gstat="$(git diff --numstat HEAD -- "$mf" 2>/dev/null)"; gins="$(echo "$gstat" | awk '{print $1}')"; gdel="$(echo "$gstat" | awk '{print $2}')"
    [ -n "$gdel" ] && [ "$gdel" -gt 12 ] && [ "$gdel" -gt "$(( ${gins:-0} * 2 ))" ] && \
      printf -- '- [guard] %s DESTRUCTIVE edit on %s (-%s +%s): likely dropped existing content\n' "$(basename "$CARD" .md)" "$mf" "$gdel" "${gins:-0}" >> "$ROOT/loop/state/journal.md"
  done

  if [ "${LOOP_CHECKER:-codex}" != "off" ]; then
    CHECKER_OUT=""; CHECKER_V=""; CHECKER_F=0
    run_checker 1 || true
    # v5.7.2 convergence-gated re-rolls: pour free local tokens WHILE findings drop
    # (up to a high cap), abort the instant they plateau (the maker is stuck). Findings
    # count is the "40->70->90%" gradient. Prompt-variation breaks tail-chasing ruts.
    REROLL=0; PREV_F="$CHECKER_F"; CAP="${SEMANTIC_REROLLS:-5}"
    while [ "${CHECKER_V:-}" = "VERDICT: FAIL" ] && [ "$REROLL" -lt "$CAP" ]; do
      REROLL=$(( REROLL + 1 ))
      case "$REROLL" in
        1) VAR="Fix EXACTLY these findings, smallest edits, keep everything else." ;;
        2) VAR="The reviewer STILL rejects it. Re-read the card's SPEC line by line and close every gap the findings name. No superficial patching." ;;
        *) VAR="Rejected $REROLL times. STEP BACK: reconsider the STRUCTURE of your solution, not small patches. Re-read the card GOAL and rebuild the weak part cleanly." ;;
      esac
      echo "[reroll] semantic re-roll $REROLL (prev findings ${PREV_F}, variation $REROLL)"
      printf -- '- [reroll] %s attempt %s (findings %s)\n' "$(basename "$CARD" .md)" "$REROLL" "$PREV_F" >> "$ROOT/loop/state/journal.md"
      SRP="$(constitution)

########################################################################
## REVIEW-DRIVEN REPAIR
########################################################################
A senior reviewer inspected your uncommitted work for the card below and REJECTED it.
$VAR
Do not argue, do not start over from scratch unless the instruction above says to.

## ORIGINAL TASK CARD
$(cat "$CARD")
$MODIFY_CTX

## REVIEWER FINDINGS (authoritative)
$(printf '%s' "$CHECKER_OUT" | tail -c 4000)

Apply the fixes now, then stop."
      { echo; echo "########## SEMANTIC RE-ROLL $REROLL $(date) ##########"; echo "########## RE-ROLL RESPONSE ##########"; } >> "$LOG"
      invoke_maker "$SRP" 1200 || true
      rm -rf "$ROOT/tmp" "$ROOT/Users" "$ROOT/src" 2>/dev/null
      if ! compile_repair 1; then CHECKER_V="VERDICT: FAIL"; break; fi
      run_checker "$(( REROLL + 1 ))" || true
      # convergence gate: findings must STRICTLY DROP, else the maker is stuck -> stop.
      if [ "${CHECKER_V:-}" = "VERDICT: FAIL" ] && [ "${CHECKER_F:-99}" -ge "$PREV_F" ]; then
        echo "[reroll] STUCK: findings ${PREV_F} -> ${CHECKER_F} (no progress), aborting re-rolls"
        printf -- '- [reroll] %s STUCK findings %s->%s\n' "$(basename "$CARD" .md)" "$PREV_F" "$CHECKER_F" >> "$ROOT/loop/state/journal.md"
        break
      fi
      PREV_F="$CHECKER_F"
    done

    V="$(printf '%s' "${CHECKER_V:-}" | grep -oiE 'PASS|FAIL' | tail -1)"
    # FAIL-CLOSED (review OV-2): checker enabled but produced NO verdict = infra hiccup.
    # Retry once; if still nothing, treat as FAIL. A blocking gate must never vanish silently.
    if [ -z "$V" ]; then
      echo "[checker] no verdict, retrying once (fail-closed)"
      run_checker "retry" || true
      V="$(printf '%s' "${CHECKER_V:-}" | grep -oiE 'PASS|FAIL' | tail -1)"
      [ -z "$V" ] && V="FAIL"
    fi
    # v6.50 (pilote): un FAIL avec 0 finding parse ET un vrai verdict emis est souvent
    # un rate de parse de la liste; mettre en file un fix-lot vide brule un cycle sur un
    # no-op. Re-revue UNE fois (l'option sure du pilote) et on garde le resultat: le cas
    # courant (parse-miss transitoire) fait surgir les findings; un vrai FAIL reste FAIL.
    # Garde: ne se declenche QUE si un verdict a reellement ete emis (CHECKER_V non vide),
    # jamais sur le cas fail-closed (aucun verdict = infra, deja traite en FAIL au-dessus).
    if [ "$V" = "FAIL" ] && [ "${CHECKER_F:-0}" -eq 0 ] && [ -n "${CHECKER_V:-}" ]; then
      echo "[checker] FAIL a 0 finding parse (malforme probable): re-revue une fois"
      run_checker "zero-findings-retry" || true
      _V2="$(printf '%s' "${CHECKER_V:-}" | grep -oiE 'PASS|FAIL' | tail -1)"
      [ -n "$_V2" ] && V="$_V2"
    fi
    echo "$V" > "$VERDICT_FILE"
    echo "[checker] final: $V after $REROLL re-roll(s)"
    printf -- '- [checker] %s FINAL %s (rerolls %s, maker %s)\n' "$(basename "$CARD" .md)" "$V" "$REROLL" "$MAKER" >> "$ROOT/loop/state/journal.md"
  fi
fi
exit "$rc"
