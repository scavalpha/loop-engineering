#!/usr/bin/env bash
# CONTRAT D'ADAPTATION STACK (v1, portabilite). Le loop est generique: ce fichier
# contient tout ce qui sait QUEL stack on construit. Porter le loop sur un autre
# projet = ecrire ce fichier pour le nouveau stack (loop-init.sh seme un squelette).
# Chaque variable a un defaut identique dans la loi: un stack.sh absent ou partiel
# ne casse JAMAIS un run (meme doctrine de degradation que MLX vers ollama).
# v2 (v6.43): les COMMANDES sont contractuelles. Spec complete: loop/STACK-CONTRACT.md
# (avec exemples api-only .NET et Flutter mobile). La loi ne connait plus npm/ng/mvnw.
STACK_NAME="angular-spring"
ARCH_PROFILE="web-fullstack"   # web-fullstack | api-only | mobile | lib | cli
BACK_DIR="backend"
FRONT_DIR="frontend"
BACK_PORT="8081"
BACK_PROC_PATTERN='myproject|spring-boot|\bjava\b'
E2E_BACK_START='./mvnw -q spring-boot:run'
FRONT_E2E_CMD='npx playwright test --reporter=line'
E2E_SENTINEL="frontend/node_modules/@playwright"
DB_PORT="5432"
HEALTH_OK_PATTERN='"UP"'
STACK_INSTALL_SENTINEL="frontend/node_modules"
STACK_INSTALL_CMD='cd frontend && npm ci --silent'
GATE_FRONT_CMD='npx ng build'
# GATE_BACK_CMD: OMISE => defaut loi (resolution mvnd/mvnw, test-compile). v6.45.1 BUG C:
# ne JAMAIS livrer une variable VIDE pour dire "defaut loi" ('' re-clobbere le defaut a
# tout re-source; 9 faux REDCOMPILE chez eagrement). Omettre = la loi decide.
TOOLCHAIN_HINT='mvnd/mvnw with the installed JDK, npx ng'
EYE_SRC_EXTS="ts java"
EYE_ENTITY_EXT="java"
stack_maker_env(){ local J="$HOME/.sdkman/candidates/java/current"; [ -d "$J" ] && export JAVA_HOME="$J"; return 0; }
# yeux mecaniques du cartographe (ce que "regarder l'app" veut dire sur ce stack)
EYE_FRONT_SRC="frontend/src/app"
# v6.50.4 (eagrement: FAUX front vide). Angular 21 standalone range les ecrans en
# items-fonctionnalite directement sous src/app (accueil/, depot/...), pas dans pages/.
# Un EYE_PAGES_DIR=.../pages fixe compte 0 => faux "front vide" => injection socle + crash.
# Defaut = src/app (convention standalone majoritaire); un projet a item pages/ surcharge.
EYE_PAGES_DIR="frontend/src/app"
EYE_CLICK_PATTERN='(click)'
EYE_STATIC_PATTERN='EXEMPLE\|Exemple\|sample'
EYE_ENTITY_PATTERN='@Entity'
EYE_ENTITY_DIR="backend/src/main/java"
EYE_SEEDER_FILE="backend/src/main/java/com/app/credit/client/config/DataSeeder.java"
EYE_MAQ_DIR="design/screens"
EYE_E2E_GLOB="frontend/e2e/*.spec.ts"
# v6.50.2 (critic produit, eagrement): routes a capturer, contractuel et RECOMMANDE
# (deterministe, inclut les routes a parametre que le scan jette). Vide = le critic scanne
# app.routes.ts en fallback. EYE_ROUTE_SAMPLE = valeur concrete pour :token/:id (token de
# demo du seeder), pour que verification/:token soit rendue au lieu d'echouer.
EYE_ROUTES=""                     # ex: "/ /depot /demandeur /instruction /commission"
EYE_ROUTE_SAMPLE="demo"           # substitue les segments :token/:id lors du scan
SMOKE_PATH="/api/items"
HEALTH_PATH="/actuator/health"
# v6.18: crochets d'usage frontier (voies non interactives, remontees par le loop eagrement).
# claude: endpoint OAuth officiel (meme token que le CLI, trousseau); codex: rate_limits en JSONL.
USAGE_CLAUDE_CMD='TOK=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin)[\"claudeAiOauth\"][\"accessToken\"])" 2>/dev/null); [ -n "$TOK" ] && curl -s --max-time 10 "https://api.anthropic.com/api/oauth/usage" -H "Authorization: Bearer $TOK" -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null | python3 -c "import json,sys;d=json.load(sys.stdin);print(\"claude5h\",int(d[\"five_hour\"][\"utilization\"]))" 2>/dev/null'
USAGE_CODEX_CMD='N=$(ls -t "$HOME"/.codex/sessions/*/*/*/*.jsonl 2>/dev/null | head -1); [ -n "$N" ] && echo "codex5h $(grep -o "\"rate_limits\":{[^}]*\"used_percent\":[0-9.]*" "$N" 2>/dev/null | tail -1 | grep -o "[0-9.]*$")"'
# --- A REMPLIR par projet (le pack est un TEMPLATE, ces deux champs sont l'identite) ---
PROJECT_DOMAIN="A REMPLIR: le domaine du projet en une phrase (injecte dans tous les prompts)"
STACK_BRIEF="## Stack
- A REMPLIR: frameworks, items, base de donnees, identifiants locaux, tokens CSS.
## Code idioms
- A REMPLIR: conventions Java/Angular, commandes de build et de test pour verifier.
(modele complet: le loop/stack.sh de myproject)"
