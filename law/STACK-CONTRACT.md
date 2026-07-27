# Contrat stack v2, la spec de portabilité du loop

La loi (loop-overnight.sh, run-cycle.sh, e2e.sh, distiller, harnais) est UNIVERSELLE:
elle ne contient aucune commande ni chemin spécifique à un langage, hors lignes de défaut
marquées `# stack-default` (comportement historique angular-spring, utilisées seulement
si le contrat ne fournit rien). Tout ce qui sait QUEL stack on construit vit dans
`loop/stack.sh`, copié depuis un modèle `loop/stack.d/<stack>.sh` par loop-init.sh.

Porter le loop sur un nouveau stack (Flutter, PHP, .NET, Rust...) = écrire un stack.sh.
Aucune modification de la loi. Une garde anti-fuite dans le harnais casse les tests si
une commande stack réapparaît dans la loi hors ligne `# stack-default`.

## Variables d'identité (obligatoires)

| Variable | Rôle | Exemple angular-spring |
|---|---|---|
| STACK_NAME | nom du stack, logs et rapports | `angular-spring` |
| ARCH_PROFILE | `web-fullstack`, `api-only`, `mobile`, `lib`, `cli` | `web-fullstack` |
| PROJECT_DOMAIN | une phrase, le domaine métier (injectée dans la constitution) | `une application web de gestion` |
| BACK_DIR / FRONT_DIR | dossiers des modules (FRONT_DIR vide si api-only/lib/cli) | `backend` / `frontend` |
| BACK_PORT | port du service | `8081` |
| STACK_BRIEF | bloc markdown: stack, idiomes de code, commandes de vérification (injecté dans chaque prompt maker via {{STACK_BRIEF}}) | voir stack.sh |

## Commandes contractuelles (v2)

| Variable | Rôle | Défaut loi (# stack-default) |
|---|---|---|
| STACK_INSTALL_CMD | installer les dépendances une fois par worktree | `npm ci` si package.json présent, sinon rien |
| STACK_INSTALL_SENTINEL | chemin dont l'existence signifie « déjà installé » | `$FRONT_DIR/node_modules` |
| GATE_FRONT_CMD | build de vérification front, exécuté depuis FRONT_DIR | `npx ng build` |
| GATE_BACK_CMD | compile+tests rapides back (gate lite), exécuté depuis BACK_DIR | `$MVN -q test-compile` (résolution mvnd/mvnw) |
| VERIFY_BACK_CMD | suite de tests complète back (gate final) | `$MVN -q test` |
| BOOT_BACK_CMD | démarrer le back pour la fumée runtime | `$MVN spring-boot:run` |
| TOOLCHAIN_HINT | texte outillage pour prompts maker/checker | `mvnd/mvnw with the installed JDK, npx ng` |
| stack_maker_env() | fonction: exporte l'env outillage (JAVA_HOME...) | JDK sdkman si présent |

## Yeux mécaniques du cartographe

| Variable | Rôle |
|---|---|
| EYE_FRONT_SRC / EYE_PAGES_DIR | où vivent les sources front et les pages/écrans |
| EYE_SRC_EXTS | extensions scannées, séparées par espaces (`ts java`, `dart`, `php`, `cs`) |
| EYE_ENTITY_PATTERN / EYE_ENTITY_DIR / EYE_ENTITY_EXT | comment reconnaître une entité du domaine |
| EYE_CLICK_PATTERN / EYE_STATIC_PATTERN | interaction réelle vs contenu d'exemple |
| EYE_SEEDER_FILE | le seeder de données |
| EYE_MAQ_DIR / EYE_E2E_GLOB | maquettes et specs e2e |

## Runtime et e2e

| Variable | Rôle | Défaut |
|---|---|---|
| SMOKE_PATH / HEALTH_PATH | endpoints de fumée et de santé | `/actuator/health` |
| HEALTH_OK_PATTERN | motif qui prouve la santé dans la réponse | `"UP"` |
| E2E_BACK_START / FRONT_E2E_CMD | démarrer le back, lancer l'e2e | spring-boot:run / playwright |
| E2E_SENTINEL | existence = e2e exécutable, sinon SKIP propre | `node_modules/@playwright` |
| DB_PORT | port de la base pour le pré-check e2e | `5432` |
| BACK_PROC_PATTERN | motif des processus du back (kills PID-scopés) | |

## Crochets d'usage frontier (optionnels)

USAGE_CLAUDE_CMD / USAGE_CODEX_CMD: une commande qui imprime `<nom> <pourcent>` pour la
sentinelle de quota. Voir le stack.sh de votre projet pour les implémentations de référence.

## Exemple, api-only .NET

```bash
STACK_NAME="dotnet-api"; ARCH_PROFILE="api-only"
BACK_DIR="src/Api"; FRONT_DIR=""; BACK_PORT="5000"
STACK_INSTALL_CMD='dotnet restore'; STACK_INSTALL_SENTINEL="src/Api/obj"
GATE_BACK_CMD='dotnet build --nologo -v q && dotnet test --nologo -v q'
TOOLCHAIN_HINT='dotnet CLI (build, test, run)'
EYE_SRC_EXTS="cs"; EYE_ENTITY_PATTERN='class .*Entity'; EYE_ENTITY_EXT="cs"
HEALTH_PATH="/healthz"; HEALTH_OK_PATTERN='Healthy'
stack_maker_env(){ export DOTNET_CLI_TELEMETRY_OPTOUT=1; }
```

## Exemple, Flutter mobile

```bash
STACK_NAME="flutter"; ARCH_PROFILE="mobile"
FRONT_DIR="app"; BACK_DIR=""   # back distant, hors repo
STACK_INSTALL_CMD='cd app && flutter pub get'; STACK_INSTALL_SENTINEL="app/.dart_tool"
GATE_FRONT_CMD='flutter analyze && flutter build web --no-pub'
TOOLCHAIN_HINT='flutter CLI (analyze, test, build)'
EYE_SRC_EXTS="dart"; EYE_PAGES_DIR="app/lib/screens"; EYE_CLICK_PATTERN='onPressed|onTap'
FRONT_E2E_CMD='flutter test integration_test'; E2E_SENTINEL="app/integration_test"
```

## Doctrine

0. **Ne JAMAIS livrer une variable vide (`VAR=''`) pour dire « défaut loi ». OMETTRE la
   variable.** Une valeur vide re-clobbère le défaut à tout re-source du contrat, et une
   commande vide fabrique du `bash -c "cd ... && "` (syntax error). BUG C du 08/07 chez
   pilote: `GATE_BACK_CMD=''` livré par le pack a produit 9 faux REDCOMPILE (compile
   sans classpath, cascade « package does not exist » sur du code correct). La loi ne
   source le contrat qu'UNE fois par script, en tête, avant ses défauts, gardé par tests.
1. Un stack.sh absent ou partiel ne casse jamais un run: chaque variable a un défaut
   `# stack-default` dans la loi, identique au comportement historique angular-spring.
2. La loi n'exécute et n'injecte QUE des variables du contrat. Toute nouvelle commande
   stack dans la loi doit passer par une variable contractuelle, la garde anti-fuite
   du harnais échoue sinon.
3. Les mécanismes front (socle injecté, œil pages, gate front) sont conditionnés par
   ARCH_PROFILE: un projet api-only, lib ou cli ne les subit pas.
4. Les CARTES et le STACK_BRIEF restent des données: elles peuvent citer mvnw ou ng
   librement, c'est leur rôle (le carto écrit les probes avec la toolchain du stack).
