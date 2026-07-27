#!/usr/bin/env bash
# v6.50 THE PRODUCT CRITIC (oeil produit). Design validated by hand on the pilote loop.
#
# WHY: every other node is CONVERGENT toward the cahier. At full coverage the loop is
# structurally "done" yet the app is raw, because nothing in the loop ever RENDERS a
# screen: probes grep text, the gate compiles, the chair reads diffs. Nobody looks. A
# product's core use case is stable but its quality has no ceiling (YouTube, 15 years,
# same use case). This is the ONE divergent node that ratchets the spec upward.
#
# SENSE  boot the app (stack contract), Playwright full-page screenshots of every route,
#        desktop 1440x900 + mobile 390x844. Zero new deps (uses the front's playwright).
# JUDGE  a VISION model (LOOP_CRITIC_MODEL) reviews the screenshots against the maquettes
#        (EYE_MAQ_DIR), the design system (design/DESIGN-stitch.md) and its own living
#        annex (docs/ameliorations.md). Product-owner + designer lens, NOT code review.
# EMIT   (a) appends findings + opposable product RULES to docs/ameliorations.md (the
#        chair can cite them); (b) seeds 60-* amelioration cards with tight AND-probes
#        citing the maquette/rule they serve. Same queue, same gate/chair downstream.
#
# GUARDRAILS: scope-frozen core (may improve HOW use cases feel, NEVER add domains/actors;
# new-scope ideas go to a PROPOSALS section for human GO). Budget: while coverage < 100%,
# max LOOP_CRITIC_MAX (default 3) cards/run at VALUE P2/P3; at full coverage it becomes the
# primary generator. Anti-taste-drift: every card MUST cite a maquette/rule/reference; the
# chair rejects vibes-only cards. MODEL is configurable (owner requirement), vision is the
# hard requirement: if the configured model / playwright / routes are absent, SKIP cleanly
# like the council skips with no chair. Runs once per run at CLOSE (after the last lot), so
# it can never cost a green. Standalone: bash loop/critic.sh <worktree>
set -uo pipefail
WT="${1:-$PWD}"; cd "$WT" || exit 0
[ -f loop/stack.sh ] && . loop/stack.sh 2>/dev/null
: "${FRONT_DIR:=}"; : "${BACK_DIR:=}"; : "${BACK_PORT:=8080}"
: "${ARCH_PROFILE:=web-fullstack}"
: "${EYE_MAQ_DIR:=design/screens}"
CRITIC_MODEL="${LOOP_CRITIC_MODEL:-claude-fable-5}"   # owner-configurable; vision REQUIRED
MAX="${LOOP_CRITIC_MAX:-3}"
skip(){ echo "[critic] SKIP: $1"; exit 0; }

# --- prerequisites: a front to render, playwright, a vision-capable CLI ---
[ "${LOOP_CRITIC:-1}" = 1 ] || skip "desactive (LOOP_CRITIC=0)"
case "$ARCH_PROFILE" in api-only|lib|cli) skip "profil $ARCH_PROFILE sans front a rendre" ;; esac
[ -n "$FRONT_DIR" ] && [ -d "$FRONT_DIR" ] || skip "pas de FRONT_DIR a rendre"
# v6.50.2 (pilote: le pack angular-spring n'installe pas @playwright, les e2e passent
# par npx -y a la demande => le critic SKIPait toujours). On accepte le fallback npx -y
# (zero dep, telecharge a la volee) si le paquet local est absent. Skip seulement si NI
# l'un NI l'autre n'est utilisable.
if [ -d "$FRONT_DIR/node_modules/@playwright" ]; then PW="npx playwright"
elif command -v npx >/dev/null 2>&1; then PW="npx -y playwright"
else skip "ni @playwright local ni npx: pas de rendu possible"; fi
command -v claude >/dev/null 2>&1 || skip "CLI vision (claude) absent"

# --- SENSE: routes to shoot. Contractual (EYE_ROUTES) d'abord, sinon scan, sinon '/' ---
# v6.50.2 (pilote: le scan ne trouvait que '/' sur un app.routes.ts standalone Angular
# 21 riche). Deux causes corrigees: (a) le scan cherchait dans FRONT_DIR/src mais rg peut
# manquer selon le format; on scanne aussi les .routes.ts explicitement et on accepte les
# guillemets simples ET doubles. (b) les routes parametrees (verification/:token) etaient
# JETEES par grep -v ':' alors que ce sont souvent les ecrans-cle: on les garde et on
# substitue un exemple concret via EYE_ROUTE_SAMPLE (token de demo du seeder). Le contrat
# EYE_ROUTES reste prioritaire et recommande (deterministe, inclut les routes a parametre).
ROUTES="${EYE_ROUTES:-}"
if [ -z "$ROUTES" ] && command -v rg >/dev/null 2>&1; then
  ROUTES="$(rg --no-messages -oE "path: *['\"][^'\"]*['\"]" "$FRONT_DIR/src" 2>/dev/null \
    | sed -E "s/path: *['\"]([^'\"]*)['\"]/\1/" | grep -vE '\*\*' \
    | sed "s#:[a-zA-Z_]*#${EYE_ROUTE_SAMPLE:-demo}#g" \
    | sed 's#^#/#; s#^//#/#' | sort -u | head -12 | tr '\n' ' ')"
fi
ROUTES="${ROUTES:-/}"
echo "[critic] routes: $ROUTES"

# v6.69: TMPDIR pointe /var/folders, ILLISIBLE par le juge vision (Read/cat/cp refuses
# par le sandbox du CLI): 13 passes critiques consecutives AVEUGLES, chaque "passe
# produit" etait en realite une passe code. Regle du 2026-07-10 enfin appliquee: les
# captures vivent sous /tmp REEL, lisible par le juge.
SHOTS="$(mktemp -d "/tmp/critic-shots-XXXXXX")"
BOOT_BACK_CMD="${BOOT_BACK_CMD:-./mvnw -q spring-boot:run}"   # stack-default
FRONT_SERVE_CMD="${FRONT_SERVE_CMD:-npx ng serve --port 4299}"  # stack-default
FRONT_PORT="${FRONT_CRITIC_PORT:-4299}"
BACK_PID=""; FRONT_PID=""
cleanup(){ [ -n "$FRONT_PID" ] && { pkill -P "$FRONT_PID" 2>/dev/null; kill "$FRONT_PID" 2>/dev/null; }
  [ -n "$BACK_PID" ] && { pkill -P "$BACK_PID" 2>/dev/null; kill "$BACK_PID" 2>/dev/null; }
  rm -rf "$SHOTS" 2>/dev/null; }
trap cleanup EXIT

# boot back (best-effort; a front that renders without live data still shows layout/taste)
if [ -n "$BACK_DIR" ] && [ -d "$BACK_DIR" ]; then
  ( cd "$BACK_DIR" && timeout 400 $BOOT_BACK_CMD >/tmp/critic-back.log 2>&1 ) & BACK_PID=$!
fi
( cd "$FRONT_DIR" && timeout 400 $FRONT_SERVE_CMD >/tmp/critic-front.log 2>&1 ) & FRONT_PID=$!
# wait for the front to answer (up to ~90s)
up=""; for _i in $(seq 1 45); do
  curl -fsS --max-time 3 "http://localhost:$FRONT_PORT/" >/dev/null 2>&1 && { up=1; break; }
  sleep 2
done
[ -n "$up" ] || skip "le front ne demarre pas sur :$FRONT_PORT (voir /tmp/critic-front.log)"

# v6.75/76 (demande pilote 17/07: routes protegees capturees comme page de connexion, le
# critic seme des cartes aveugles sur le coeur du produit). Session authentifiee par CONTRAT
# (la loi ne connait ni la cle, ni la forme du jeton, ni le store):
#   - EYE_SESSION_KEY + EYE_SESSION_TOKEN_CMD => session injectee (sinon captures anonymes, v6.60).
#   - EYE_SESSION_STORAGE ('local'|'session', defaut local) => store cible cote navigateur.
#   - EYE_ROUTE_ROLES (v6.76, map '/route=ROLE ...') => une session PAR ROLE, resolue en
#     invoquant EYE_SESSION_TOKEN_CMD avec le role en $1, cache par role. Une route hors map
#     est capturee en anonyme (publique). Sans EYE_ROUTE_ROLES => jeton unique pour toutes
#     les routes (comportement v6.75, l'admin voit tout). Retro-compatible dans les 2 sens.
EYE_STORE_ARG=""; [ "${EYE_SESSION_STORAGE:-local}" = "session" ] && EYE_STORE_ARG="session"
_TOKCACHE="$SHOTS/.tokcache"; mkdir -p "$_TOKCACHE"
route_role(){ # $1=route -> imprime le role mappe, vide si absent (pas de tableau assoc: bash 3.2)
  local r="$1" pair
  for pair in ${EYE_ROUTE_ROLES:-}; do
    case "$pair" in "${r}="*) printf '%s' "${pair#*=}"; return ;; esac
  done
}
resolve_token(){ # $1=role (vide = mode jeton unique). Cache par role. Extraction NEUTRE:
  # head -c (cap taille) + $() strip le \n final, sans detruire les espaces internes d'un
  # jeton JSON (remontee pilote: tr -d '[:space:]' cassait les valeurs JSON). Non-vide requis.
  local role="$1" cf t
  cf="$_TOKCACHE/$(printf '%s' "${role:-_single}" | tr -c 'a-zA-Z0-9' '_')"
  [ -f "$cf" ] && { cat "$cf"; return; }
  t="$(timeout 20 bash -c "$EYE_SESSION_TOKEN_CMD" _critic "$role" 2>/dev/null | head -c 8192)"
  printf '%s' "$t" > "$cf"; printf '%s' "$t"
}
session_arg_for(){ # $1=route -> imprime "cle=jeton" a injecter, vide si anonyme
  [ -n "${EYE_SESSION_KEY:-}" ] && [ -n "${EYE_SESSION_TOKEN_CMD:-}" ] || return 0
  local r="$1" role tok
  if [ -n "${EYE_ROUTE_ROLES:-}" ]; then
    role="$(route_role "$r")"; [ -n "$role" ] || return 0   # hors map = anonyme (public)
    tok="$(resolve_token "$role")"
  else
    tok="$(resolve_token "")"                                # jeton unique
  fi
  [ -n "$tok" ] && printf '%s=%s' "$EYE_SESSION_KEY" "$tok"
}
if [ -n "${EYE_SESSION_KEY:-}" ] && [ -n "${EYE_SESSION_TOKEN_CMD:-}" ]; then
  echo "[critic] session authentifiee par contrat (cle $EYE_SESSION_KEY, store ${EYE_SESSION_STORAGE:-local}${EYE_ROUTE_ROLES:+, par role})"
fi

shoot(){ # $1=route $2=label $3=WxH
  # v6.50.2 (pilote, "lab: unbound variable" x2 sous bash 3.2 macOS): le local
  # multi-assignation ne se comporte pas comme bash 5, chaque capture mourait. Une
  # declaration par ligne (famille def-avant-usage, variante portabilite bash 3.2).
  local r="$1"; local lab="$2"; local size="$3"
  local out="$SHOTS/${lab}$(echo "$r" | sed 's#[/]#_#g').png"
  local sess; sess="$(session_arg_for "$r")"   # v6.76: session par route (ou unique, ou anonyme)
  # v6.60: capture CONFINEE. Le CLI `playwright screenshot` ne lit pas playwright.config.ts
  # -> chromium GPU-ON (vecteur des reboots machine, cf v6.59). Si le module playwright est
  # resolvable localement, on passe par critic-shot.mjs: launch args GPU-off explicites +
  # passe d'interaction scroll bas/haut avant capture (un ecran qui blanchit au scroll
  # apparait blanc, le juge vision le voit). Fallback CLI conserve uniquement si le module
  # est absent (rare, risque documente).
  # v6.60.1: le worktree est le cwd du critic (WT, cd ligne 28), pas $ROOT (variable
  # inexistante ici, set -u la tuait: 16 captures mortes le 14/07, critique SKIP).
  local SHOT_MJS="$WT/loop/critic-shot.mjs"
  if [ -f "$SHOT_MJS" ] && [ -d "$FRONT_DIR/node_modules/playwright" ]; then
    ( cd "$FRONT_DIR" && timeout 90 node "$SHOT_MJS" \
        "http://localhost:$FRONT_PORT$r" "$out" "$size" ${sess:+"$sess" ${EYE_STORE_ARG:+"$EYE_STORE_ARG"}} >/dev/null 2>&1 ) || true
  else
    ( cd "$FRONT_DIR" && timeout 90 $PW screenshot --full-page \
        --viewport-size="$size" "http://localhost:$FRONT_PORT$r" "$out" >/dev/null 2>&1 ) || true
  fi
  [ -s "$out" ] && echo "$out"
}
SHOT_LIST=""
for r in $ROUTES; do
  d="$(shoot "$r" desktop 1440,900)"; [ -n "$d" ] && SHOT_LIST="$SHOT_LIST $d"
  m="$(shoot "$r" mobile 390,844)";  [ -n "$m" ] && SHOT_LIST="$SHOT_LIST $m"
done
SHOT_LIST="${SHOT_LIST# }"
# v6.59: reap chromium des screenshots (vecteur reboot GPU) avant la phase de jugement.
pkill -f 'headless_shell' 2>/dev/null; pkill -f 'Chromium.*--headless' 2>/dev/null
[ -n "$SHOT_LIST" ] || skip "aucune capture produite (rendu vide)"
echo "[critic] captures: $(echo "$SHOT_LIST" | wc -w | tr -d ' ')"

# --- JUDGE + EMIT: a vision model reads the shots + references, returns findings + cards ---
mkdir -p docs loop/tasks
[ -f docs/ameliorations.md ] || printf '# Ameliorations produit (annexe vivante du critique)\n\n## Regles produit opposables\n\n## PROPOSALS (hors scope, GO humain requis)\n' > docs/ameliorations.md
MAQ_LIST="$(ls "$EYE_MAQ_DIR"/*.png "$EYE_MAQ_DIR"/*.jpg 2>/dev/null | head -30 | tr '\n' ' ')"
COV_LINE="$(ls docs/coverage.md >/dev/null 2>&1 && echo "Couverture actuelle: $(grep -c 'COUVERT-VERT' docs/coverage.md 2>/dev/null) verts." || echo 'Couverture inconnue.')"

CPROMPT="Tu es le CRITIQUE PRODUIT du loop (product owner + designer), pas un reviewer de code.
Regarde l'app REELLE telle qu'un utilisateur la voit et fais monter la barre de qualite.

LIS ces captures d'ecran de l'app en cours d'execution (desktop + mobile), avec l'outil de lecture d'images:
$(printf '%s\n' $SHOT_LIST)

JUGE selon la hierarchie d'autorite (decision proprietaire, regles 3+6 de l'annexe):
- FOND (non negociable): les cas d'usage du cahier. Chaque action de l'ecran est presente
  et PRATICABLE, elements de confiance presents, aucune fuite technique (enum brut, /api/
  dans le texte, identifiants internes) montree a l'utilisateur.
- IDENTITE (non negociable): le systeme de design $( [ -f design/DESIGN-stitch.md ] && echo design/DESIGN-stitch.md || echo 'du projet') (palette, typographie, tokens).
- DIRECTION (inspiration seulement): les maquettes: $MAQ_LIST
  Elles donnent le NIVEAU et l'ambiance vises, PAS les blocs a copier. Ne demande JAMAIS
  de 'coller a la maquette'; demande de servir le cas d'usage au niveau de la maquette.
- Ton annexe vivante des regles deja etablies: docs/ameliorations.md

$COV_LINE

ORDRE DES PASSES (v6.51.1): (0) EVIDENCE DE CATEGORIE d'abord: « cette classe de produit,
qu'attend n'importe quel praticien qu'elle fasse, evidemment? » (un depot de pieces =
upload + consultation de fichiers; des roles = login; un workflow = notifications).
Chaque evidence absente des captures = carte P1 immediate, AVANT tout le reste. Puis
(1) planchers UX, (2) parcours, (3) esthetique. On ne polit pas les accents d'un produit
dont le coeur manque.

TU ES UN CLIENT MYSTERE, PAS UN CRITIQUE DE VITRINE (v6.51, retour proprietaire du pilote:
'si je run le loop 100h, il dira toujours fonctionnellement complete?'). Une app peut etre
'verte' partout et BASIQUE: champ localisation en texte libre, tableaux sans recherche ni
tri qui debordent, detail dans un panneau etroit au lieu d'une route, NNI demande a une
ENTREPRISE. Juge la TACHE de l'utilisateur, pas la reponse de l'endpoint.

PLANCHERS UX OPPOSABLES (chaque violation visible = une carte, cite le plancher):
- Tableau de donnees: recherche + tri + pagination, sinon inutilisable au-dela de 20 lignes.
- Detail d'une entite: une ROUTE dediee navigable, jamais seulement un panneau lateral.
- Localisation/adresse: structure (champs dedies ou carte), jamais un texte libre.
- Identite selon l'ENTITE: une societe a RC/NIF, une personne a NNI; un formulaire qui
  melange = non-sens metier (croiser docs/domain-rules.md).
- Dates = datepicker; valeurs finies = select alimente par le referentiel.
- Reference de niveau: les services publics numeriques exigeants (design system gov.uk,
  service-public.fr): la maquette est le PLANCHER d'ambiance, pas le plafond de qualite.

PARCOURS D'EXPERIENCE (la piece qui change tout): un cas d'usage n'est REELLEMENT couvert
que si un utilisateur ACCOMPLIT sa tache de bout en bout (remplir chaque champ, soumettre,
retrouver son enregistrement, ouvrir le detail, agir). Pour CHAQUE UC visible dans les captures
sans spec e2e de parcours ($EYE_E2E_GLOB), emets une carte 'parcours-<uc>' VALUE P1 dont le
livrable est le spec Playwright du parcours COMPLET (pas un smoke; PROBE = test -f du spec + rg des etapes, JAMAIS son execution, reservee au harnais): elle vaut plus que
toute carte cosmetique. C'est ainsi que le loop se construit ses propres sens.

REGLES DURES:
- SCOPE GELE: tu ameliores COMMENT les cas d'usage existants se presentent et se ressentent.
  Tu n'ajoutes JAMAIS de domaine, d'acteur ou de cas d'usage nouveau. Une idee hors-scope va
  dans une section PROPOSALS (GO humain requis), pas en carte.
- Chaque carte doit CITER une maquette, une regle de docs/ameliorations.md, ou une reference
  du design system. Aucune carte 'au feeling'. Le chair rejette les cartes sans reference.
- Au plus $MAX cartes, VALUE P2 ou P3, SAUF les cartes parcours-<uc> et les violations de
  PLANCHER qui sont P1 (un parcours qui ne passe pas = produit non couvert, pas cosmetique).
- Les PROBES sont en ET (rg TOKEN1 && rg TOKEN2), tokens SPECIFIQUES a l'ecran, jamais un
  test unitaire ecrit par le maker. Prouver par build vert + rg du cablage/element rendu.
- JAMAIS d'alternance '|' dans un pattern rg (une alternance = OU menteur, AUTODONE possible
  sans feature). Une PROBE par token, sur des lignes PROBE separees.

SORTIE, exactement deux blocs:

===AMELIORATIONS===
(3 a 8 lignes: constats produit + regles opposables nouvelles, style 'REGLE: <...>'. Je les
ajoute a docs/ameliorations.md. Mets les idees hors-scope sous 'PROPOSAL: <...>'.)
===END===

Puis, pour chaque carte (au plus $MAX), un bloc:
===NEW-CARD <slug-kebab>===
# <titre>
USE CASE:
<l'amelioration produit, l'ecran vise, la maquette/regle citee>
DONE WHEN:
- <critere 1 verifiable>
- <critere 2 verifiable>
SCOPE: front
VALUE: P2
DEPENDS: <si applicable>
PROBE: <rg token specifique dans le src front>
PROBE: <2e rg token specifique>
===END==="

echo "[critic] JUDGE via $CRITIC_MODEL (vision)..."
OUT="$(timeout 600 claude --model "$CRITIC_MODEL" -p "$CPROMPT" --output-format text 2>/dev/null)"
[ -n "$OUT" ] || skip "modele critique muet ou sans capacite vision ($CRITIC_MODEL)"

# EMIT (a): append findings + rules to the living annex
AMEL="$(printf '%s' "$OUT" | awk '/===AMELIORATIONS===/{f=1;next}/===END===/{if(f){exit}}f')"
if [ -n "$AMEL" ]; then
  { echo; echo "## Passe critique du $(date '+%F %H:%M')"; printf '%s\n' "$AMEL"; } >> docs/ameliorations.md
  echo "[critic] docs/ameliorations.md mis a jour"
fi

# v6.70: le semeur respecte son propre lint. Toute PROBE rg dont le pattern quote
# contient une alternance '|' (sans groupe regex) est scindee MECANIQUEMENT en une
# PROBE par token (ET). Le prompt seul ne suffit pas: probe-lint refusait au run
# suivant les cartes semees par cette meme passe (constat pilote 16/07).
split_or_probes() {
  f="$1"; tmp="$(mktemp)"
  while IFS= read -r l; do
    case "$l" in
      PROBE:*rg*\"*\|*\"*)
        pre="${l%%\"*}"; rest="${l#*\"}"; pat="${rest%%\"*}"; post="${rest#*\"}"
        case "$pat" in
          *"("*|*")"*|*"\\|"*) printf '%s\n' "$l" >> "$tmp" ;;   # groupe/echappement regex: pas touche
          *) old_ifs="$IFS"; IFS='|'
             for t in $pat; do [ -n "$t" ] && printf '%s"%s"%s\n' "$pre" "$t" "$post" >> "$tmp"; done
             IFS="$old_ifs" ;;
        esac ;;
      *) printf '%s\n' "$l" >> "$tmp" ;;
    esac
  done < "$f"
  mv "$tmp" "$f"
}

# EMIT (b): seed 60-* cards (capped at MAX), AND-probe enforced by split_or_probes
N=0
printf '%s\n' "$OUT" | awk '/===NEW-CARD/{f=1} f{print} /===END===/{if(f && !/AMELIORATIONS/)f=0}' > /tmp/critic-cards.txt 2>/dev/null || true
while IFS= read -r line; do
  case "$line" in
    ===NEW-CARD*)
      [ "$N" -ge "$MAX" ] && break
      slug="$(printf '%s' "$line" | sed -E 's/^===NEW-CARD *//; s/ *===$//' | tr -c 'a-zA-Z0-9-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')"
      [ -z "$slug" ] && slug="critique-$N"
      CARDF="loop/tasks/60-${slug}.md"; : > "$CARDF"; N=$(( N + 1 )); continue ;;
    ===END*) [ -n "${CARDF:-}" ] && split_or_probes "$CARDF"; CARDF="" ;;
    *) [ -n "${CARDF:-}" ] && printf '%s\n' "$line" >> "$CARDF" ;;
  esac
done < <(printf '%s\n' "$OUT")

if [ "$N" -gt 0 ]; then
  git add docs/ameliorations.md loop/tasks/60-*.md 2>/dev/null
  git commit -q -m "critic: $N cartes amelioration produit + regles [loop]" 2>/dev/null || true
  echo "[critic] $N carte(s) amelioration semee(s) (60-*)"
else
  git add docs/ameliorations.md 2>/dev/null && git commit -q -m "critic: regles produit mises a jour [loop]" 2>/dev/null || true
  echo "[critic] aucune carte cette passe (annexe mise a jour)"
fi
exit 0
