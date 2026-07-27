#!/usr/bin/env bash
# v6.9 C3 (portabilite): seme le loop dans un NOUVEAU projet, sur un autre stack.
#   loop-init.sh <repo-cible> [--stack <nom>]
# Copie: la LOI (scripts + tests + hooks + constitution), le savoir UNIVERSEL du store
# (lentilles + le contrat stack si un pack existe), la boite aux lettres FEEDBACK, et
# UNE carte bootstrap: le cartographe lit le cahier des charges et genere la file.
# Ne copie PAS: cartes projet, memoire maker, DECISIONS, metriques (chaque projet
# merite sa propre courbe). v1 assumee: on l'ameliorera au rythme du loop lui-meme.
set -euo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:?usage: loop-init.sh <repo-cible> [--stack <nom>]}"
STACK="generique"
[ "${2:-}" = "--stack" ] && STACK="${3:?--stack exige un nom}"
GSTORE="${LOOP_SKILLS_STORE:-$HOME/dev/loop-skills-general}"

[ -d "$TARGET" ] || { echo "[init] repo cible introuvable: $TARGET"; exit 2; }
git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || { echo "[init] pas un repo git: $TARGET"; exit 2; }
[ -e "$TARGET/loop/loop-overnight.sh" ] && { echo "[init] un loop existe deja dans $TARGET, refus d'ecraser"; exit 2; }

mkdir -p "$TARGET/loop"/{tasks,state,skills,skills-front,hints.d,reports,logs,wip,feedback,tests,stack.d} \
         "$TARGET/loop/hermes-profile/agent-hooks" "$TARGET/loop/state"/{queue,done,failed}

# 0b (v6.46, decouvert par release-smoke): HYGIENE GIT DU LOOP. Le gate revert fait
# git clean; sans ces ignores, le clean detruisait les organes runtime du loop (state,
# reports, compteurs) a CHAQUE revert -> faux "state vanished", churn infini. Le projet d'origine etait
# protege par son .gitignore historique PAR ACCIDENT; c'est desormais la loi du semis
# (et la loi exclut aussi loop/ du clean, double verrou).
for _ig in 'loop/state/' 'loop/logs/' 'loop/reports/' 'loop/wip/' 'loop/archive/' 'loop/feedback/'; do
  grep -qxF "$_ig" "$TARGET/.gitignore" 2>/dev/null || echo "$_ig" >> "$TARGET/.gitignore"
done
# v6.50 (pilote: maker-perf.tsv deja SUIVI avant l'ignore continuait a salir l'arbre
# MAIN et bloquer chaque `git merge --ff-only` du consommateur, d'ou la danse de stash).
# Le .gitignore ne desuit pas ce qui est deja suivi: on untrack les organes runtime deja
# indexes (les fichiers restent sur le disque, seul l'index les oublie).
git -C "$TARGET" rm -r --cached --quiet --ignore-unmatch \
  loop/state loop/logs loop/reports loop/wip loop/archive loop/feedback 2>/dev/null || true
echo "[init] .gitignore: organes runtime du loop proteges du git clean + untrack des deja-suivis"

# 1. la LOI, integralement (c'est elle, l'intelligence durement acquise)
for f in loop-overnight.sh run-cycle.sh verify.sh distill.sh council.sh e2e.sh \
         resurrect.sh mlx-keeper.sh setup-hermes-profile.sh afk-watch.sh \
         score-skills.sh measure-memory.sh constitution.md \
         mem-guard.sh maquette-fidelity.sh morning-digest.sh critic.sh STACK-CONTRACT.md; do
  [ -f "$SRC/$f" ] && cp "$SRC/$f" "$TARGET/loop/$f"
done
cp "$SRC/tests/harness-test.sh" "$TARGET/loop/tests/"
# v6.50 (attrape par release-smoke sur le jouet: 3 tests v646 cherchent le smoke absent):
# le smoke de release fait partie de la loi semee, un loop porte doit pouvoir se release-tester
cp "$SRC/tests/release-smoke.sh" "$TARGET/loop/tests/" 2>/dev/null || true
# v6.50: seme la taste-skill front (curable par le projet, son design system reste autoritaire)
ls "$SRC/skills-front/"*.md >/dev/null 2>&1 && cp "$SRC/skills-front/"*.md "$TARGET/loop/skills-front/" 2>/dev/null || true
cp "$SRC/loop-init.sh" "$TARGET/loop/loop-init.sh" 2>/dev/null || true
[ -d "$SRC/shims" ] && mkdir -p "$TARGET/loop/shims" && cp -R "$SRC/shims/." "$TARGET/loop/shims/"
ls "$SRC"/hints.d/* >/dev/null 2>&1 && cp "$SRC"/hints.d/* "$TARGET/loop/hints.d/" 2>/dev/null
cp "$SRC"/hermes-profile/agent-hooks/*.sh "$TARGET/loop/hermes-profile/agent-hooks/"
cp "$SRC"/stack.d/*.sh "$TARGET/loop/stack.d/" 2>/dev/null || true

# 2. le contrat stack: pack existant, sinon squelette a remplir (premiere tache humaine
#    ou premiere convocation du conseil du nouveau loop)
PROJ_SLUG="$(basename "$TARGET" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
if [ -f "$SRC/stack.d/$STACK.sh" ]; then
  cp "$SRC/stack.d/$STACK.sh" "$TARGET/loop/stack.sh"
  printf '\n# profil maker propre a CE projet (jamais partage entre loops)\nLOOP_PROFILE_DIR="$HOME/.hermes-loop-%s"\n' "$PROJ_SLUG" >> "$TARGET/loop/stack.sh"
  echo "[init] contrat stack: pack $STACK (profil maker: ~/.hermes-loop-$PROJ_SLUG)"
else
  cat > "$TARGET/loop/stack.sh" <<'STUB'
#!/usr/bin/env bash
# CONTRAT STACK, A REMPLIR (le loop tourne avec des defauts angular-spring sinon).
# Renseigne au minimum: BACK_DIR, FRONT_DIR, BACK_PORT, E2E_BACK_START, FRONT_E2E_CMD,
# puis les yeux mecaniques EYE_* (voir stack.d/angular-spring.sh comme modele complet).
STACK_NAME="a-remplir"
STACK_BRIEF="## Stack
- A REMPLIR: frameworks, dossiers, base de donnees, identifiants locaux, tokens CSS.
## Code idioms
- A REMPLIR: conventions Java/Angular/autre, commandes de build et de test pour verifier.
(modele complet: loop/stack.d/angular-spring.sh)"
STUB
  printf '\n# profil maker propre a CE projet (jamais partage entre loops)\nLOOP_PROFILE_DIR="$HOME/.hermes-loop-%s"\n' "$PROJ_SLUG" >> "$TARGET/loop/stack.sh"
  echo "[init] contrat stack: SQUELETTE a remplir (modele: loop/stack.d/angular-spring.sh)"
fi

# 2b (v6.43): conformite du contrat. Liste les variables v2 que le stack.sh seme ne
# fournit pas: chacune tournera sur son defaut angular-spring (# stack-default). Sur un
# stack NON angular-spring, chaque manque est une mine (npm ci sur du .NET = REFUS au
# lancement, classe nuit-blanche v6.42 cote stack). Bruyant a l'init, jamais bloquant.
_MISS=""
# (GATE_BACK_CMD absente de la liste: legitimement OMISE, defaut loi mvnd/mvnw. v6.45.1)
for _v in ARCH_PROFILE STACK_INSTALL_CMD GATE_FRONT_CMD TOOLCHAIN_HINT \
          EYE_SRC_EXTS EYE_ENTITY_EXT E2E_SENTINEL HEALTH_OK_PATTERN PROJECT_DOMAIN STACK_BRIEF; do
  grep -q "^$_v=" "$TARGET/loop/stack.sh" || _MISS="$_MISS $_v"
done
if [ -n "$_MISS" ]; then
  echo "[init] ATTENTION contrat incomplet, defauts angular-spring pour:$_MISS"
  echo "[init] (spec: loop/STACK-CONTRACT.md; sur un stack non angular-spring, REMPLIR avant la premiere nuit)"
else
  echo "[init] contrat stack v2 complet"
fi

# 3. le savoir universel du store (les lentilles voyagent, les idiomes stack suivent le pack)
[ -f "$GSTORE/lenses-universal.md" ] && cp "$GSTORE/lenses-universal.md" "$TARGET/loop/carto-lenses.md"

# 4. la boite aux lettres
cat > "$TARGET/loop/FEEDBACK.md" <<'FB'
<!-- Boite aux lettres du loop. Ecris librement, une idee par ligne ou paragraphe.
Le loop consomme au lancement et entre deux cycles, archive tout dans loop/feedback/
avec ce qu il a fait de chaque item, puis remet ce fichier a neuf.
URGENT en debut de ligne met la carte en tete de file.
La loi (loop/*.sh) ne se change pas ici, elle reste signee par git. -->
FB

# 5. la carte bootstrap: le cartographe EST l'organe de demarrage a froid
cat > "$TARGET/loop/tasks/01-cartographie-initiale.md" <<'CARD'
# Carte 01, cartographie initiale du projet

USE CASE:
Le loop demarre sur un projet neuf. Avant de construire, il faut savoir QUOI construire:
lire le cahier des charges (docs/), inventorier le code existant, et produire la
premiere carte d'etat qui alimentera le cartographe.

DONE WHEN:
- docs/domain-rules.md existe: les regles metier extraites du cahier, une par ligne.
- docs/night-review.md existe: etat honnete du code actuel vs le cahier (ce qui
  existe, ce qui manque, ce qui est fake).

SCOPE: full
PROBE: test -s docs/domain-rules.md
PROBE: test -s docs/night-review.md
CARD

# 6. gitignore des fichiers d'etat runtime
for line in "loop/NIGHT-PLAN" "loop/STOP" "loop/RUNNING" "loop/DEADLINE"; do
  grep -qxF "$line" "$TARGET/.gitignore" 2>/dev/null || echo "$line" >> "$TARGET/.gitignore"
done

cat > "$TARGET/loop/README-LOOP.md" <<'RD'
# Loop seme par loop-init (v1)

Rituel de lancement (JAMAIS sans ordre explicite du proprietaire, jamais quand il
travaille sur la machine):
1. Remplir loop/stack.sh si c'est un squelette.
2. Cahier des charges dans docs/ (le cartographe le lit).
3. bash loop/tests/harness-test.sh (tout doit passer).
4. rm -f loop/STOP && nohup bash loop/loop-overnight.sh +1h & (premiere heure OBSERVEE).
Prerequis machine: ollama (fallback), LM Studio + modele MLX (maker), codex CLI (juge),
hermes-agent (harnais maker), profil telegram dans ~/.hermes/.env pour les notifications.
RD

echo "[init] loop seme dans $TARGET (stack: $STACK)"
echo "[init] prochaines etapes: voir $TARGET/loop/README-LOOP.md"
