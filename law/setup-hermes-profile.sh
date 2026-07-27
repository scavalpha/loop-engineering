#!/usr/bin/env bash
# v5.9: builds the LOOP-SCOPED Hermes profile (HERMES_HOME) that carries N2+N4+N6+N1
# without ever touching the user's global ~/.hermes:
#   N2 write-boundary hook (pre_tool_call, JSON-block protocol)
#   N4 fallback_providers (ollama hiccup / empty-response retry with the OTHER local model)
#   N6 project-scoped memory (profile-scoped by construction; 3 seeded domain facts)
#   N1 LSP check (informational)
# Profile lives OUTSIDE the repo (no secrets in-repo): ~/.hermes-loop
# Usage: setup-hermes-profile.sh <worktree-root>   => exit 0 = profile ready + smoke passed
set -uo pipefail
WT="${1:?usage: setup-hermes-profile.sh <worktree-root>}"
SRC_HOME="$HOME/.hermes"
# v6.10.1: un profil maker PAR PROJET (memoire et skills du maker jamais partages
# entre deux loops). Le contrat stack du projet cible peut definir LOOP_PROFILE_DIR;
# defaut generique si le contrat ne le definit pas (continuite de la memoire accumulee).
[ -f "${1:-}/loop/stack.sh" ] && . "${1:-}/loop/stack.sh" 2>/dev/null
PROFILE="${LOOP_PROFILE_DIR:-$HOME/.hermes-loop}"
REPO_HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermes-profile/agent-hooks"
export PATH="$HOME/.local/bin:$PATH"

[ -f "$SRC_HOME/config.yaml" ] || { echo "[profile] no user config.yaml, cannot seed"; exit 1; }
mkdir -p "$PROFILE/agent-hooks"

# 1. seed from the user's working provider config (fresh each run, idempotent)
cp "$SRC_HOME/config.yaml" "$PROFILE/config.yaml"
[ -f "$SRC_HOME/.env" ] && cp "$SRC_HOME/.env" "$PROFILE/.env" && chmod 600 "$PROFILE/.env"

# 2. install the write-boundary hook
cp "$REPO_HOOKS/write-boundary.sh" "$PROFILE/agent-hooks/write-boundary.sh"
chmod +x "$PROFILE/agent-hooks/write-boundary.sh"
cp "$REPO_HOOKS/probe-verify.sh" "$PROFILE/agent-hooks/probe-verify.sh"
chmod +x "$PROFILE/agent-hooks/probe-verify.sh"

# 3. overlay loop keys (hooks + fallback + auto-accept) with pyyaml (structure-safe)
# LOOP_MLX=1: the maker's primary runtime becomes the local MLX server (port 8090,
# ~2x generation speed on Apple Silicon); the ollama endpoint stays as the fallback
# lane so the ornith escalation still resolves (MLX errors on unknown names -> hermes
# fallback_providers -> ollama). LOOP_MLX unset: ollama primary as before.
# v6.49: utiliser le python du venv HERMES pour l'overlay yaml. Le python systeme
# (/usr/bin/python3) n'a PAS toujours pyyaml (absent apres le reboot du 09/07 => overlay
# mort => 3 echecs profil => degradation ollama, la nuit blanche). Hermes lui-meme depend
# de pyyaml, donc son venv l'a TOUJOURS: on l'utilise en priorite, python3 en secours.
HERMES_PY="$HOME/.hermes/hermes-agent/venv/bin/python3"
[ -x "$HERMES_PY" ] && "$HERMES_PY" -c 'import yaml' 2>/dev/null || HERMES_PY="python3"
"$HERMES_PY" - "$PROFILE/config.yaml" "$PROFILE/agent-hooks/write-boundary.sh" "$PROFILE/agent-hooks/probe-verify.sh" <<'PY'
import os, sys, yaml
cfg_path, hook_path, verify_hook = sys.argv[1], sys.argv[2], sys.argv[3]
cfg = yaml.safe_load(open(cfg_path)) or {}
# N2: block file-tool writes outside the worktree (JSON-block protocol; matcher = write tools)
cfg["hooks"] = {
    "pre_tool_call": [{
        "matcher": "write_file|create_file|edit_file|patch|apply_patch",
        "command": hook_path,
        "timeout": 5,
    }],
    # v6.8: les PROBE de la carte dans le tour du maker (decouverte avancee des RED).
    # Le hook s'auto-limite (2 relances, cartes de code seulement); borne dure hermes: 3.
    "pre_verify": [{
        "command": verify_hook,
        "timeout": 900,
    }],
}
cfg["hooks_auto_accept"] = True  # headless run: our own reviewed hook, consent pre-granted
# capture the ORIGINAL (ollama) endpoint before any MLX override: it stays the fallback lane
primary = cfg.get("model") or {}
ollama_url = primary.get("base_url", "http://localhost:11434/v1")
if os.environ.get("LOOP_MLX") == "1":
    mlx_model = os.environ.get("LOOP_MLX_MODEL", "qwen3-coder-30b-a3b-instruct-mlx")
    # v6.49 RACINE (regression du 09/07): NE PAS heriter du provider user. L'utilisateur a
    # bascule sa config hermes de base sur provider "moa" (Mixture-of-Agents, base_url
    # moa://local, config_version 33). En heritant "moa", hermes routait CHAQUE appel maker
    # du MLX a travers l'agregateur MoA au lieu d'un appel OpenAI-compatible direct au
    # serveur LM Studio -> "API call failed after 3 retries" -> profil inadoptable ->
    # degradation ollama. Le endpoint MLX est un serveur OpenAI-compatible SIMPLE: il exige
    # un provider direct ("custom"), jamais le provider d'agregation de l'utilisateur.
    # Prouve le 09/07: provider moa -> echec; provider custom -> PONG immediat.
    cfg["model"] = {
        "default": mlx_model,
        "provider": os.environ.get("LOOP_MLX_PROVIDER", "custom"),
        "base_url": os.environ.get("LOOP_MLX_URL", "http://localhost:1234/v1"),
        # v6.42: 65536, et DOIT correspondre au contexte de CHARGE MLX (le driver charge
        # --context-length 65536). Deux contraintes dures se croisent ici:
        #   1. Hermes REFUSE tout modele declare < 64000 ("below the minimum 64,000
        #      required by Hermes Agent", smoke de la nuit du 08/07).
        #   2. Le mismatch declare > charge fait deborder les prompts -> reponses vides.
        # v6.39.1 avait aligne vers le BAS (32768): Hermes a refuse le profil, le driver
        # est retombe sur le profil user qui ne connait pas le nom MLX -> HTTP 404 -> 96
        # cycles muets, nuit blanche. L'alignement correct est vers le HAUT: 65536 des
        # deux cotes (KV cache ~+3Go, tenable seul en memoire sur 48Go).
        "context_length": 65536,
    }
    print("[profile] MLX primary: %s" % mlx_model)
# N4 (v6.34): fallback on API errors / empty responses only. Doit etre un modele LEGER
# qui COEXISTE avec MLX en memoire unifiee. ornith-cc (26Go) + MLX (17Go) = 43Go = crash
# sur 48Go (2026-07-08). LOOP_FALLBACK_MODEL (defaut qwen3:14b ~9Go) tient (17+9=26Go).
# La fallback = DISPONIBILITE, pas qualite; un petit modele suffit. Escalade = separee.
import os as _os
if _os.environ.get("LOOP_MLX") == "1":
    # MLX primaire: UN SEUL modele local, pas de fallback (deux LLM = crash memoire 48Go).
    cfg["fallback_providers"] = []
    print("[profile] MLX primaire: aucune fallback locale (un seul modele resident)")
else:
    _fbm = _os.environ.get("LOOP_FALLBACK_MODEL", "qwen3:14b")
    fb = {"provider": primary.get("provider", "custom"), "model": _fbm, "base_url": ollama_url}
    if primary.get("key_env"):
        fb["key_env"] = primary["key_env"]
    cfg["fallback_providers"] = [fb]
yaml.safe_dump(cfg, open(cfg_path, "w"), sort_keys=False, allow_unicode=True)
print("[profile] config overlaid: hooks + fallback_providers + auto-accept")
PY
[ $? -eq 0 ] || { echo "[profile] yaml overlay failed"; exit 1; }

# 4. v6.53: seed les faits de domaine dans la memoire BUILT-IN de hermes. Diagnostic 11/07:
#    'hermes memory add/store' N'EXISTE PAS en v0.18 (memory = {setup,status,off,reset}),
#    d'ou "memory CLI absent" pendant des semaines. La memoire built-in est TOUJOURS active
#    et vit dans $PROFILE/memories/MEMORY.md (markdown, comme ma propre memoire): on ECRIT
#    dedans directement, dedup par ligne. C'est aussi la cible du pont Opus->Hermes (le
#    driver y verse les lecons du run a la fermeture, cf memory_bridge).
MEMDIR="$PROFILE/memories"; mkdir -p "$MEMDIR"; MEMF="$MEMDIR/MEMORY.md"
[ -f "$MEMF" ] || printf '# MEMORY\n\n## Faits de domaine (loop)\n' > "$MEMF"
seed_mem(){ grep -qF -- "$1" "$MEMF" 2>/dev/null || printf -- '- %s\n' "$1" >> "$MEMF"; }
MEMOK=0
seed_mem "Project: money amounts are ALWAYS BigDecimal (never double/float)." && MEMOK=$((MEMOK+1))
seed_mem "Project: not-found on update/get maps NoSuchElementException to HTTP 404 (existing handler)." && MEMOK=$((MEMOK+1))
seed_mem "Project front: Angular standalone components + signals ONLY, no NgModules, templateUrl pattern." && MEMOK=$((MEMOK+1))
echo "[profile] memory seeds: $MEMOK/3 -> $MEMF (built-in, toujours active)"

# 5. N1: LSP state under the profile (informational)
HERMES_HOME="$PROFILE" timeout 20 hermes lsp status 2>/dev/null | grep -E "enabled|active clients" | head -2 | sed 's/^/[profile] lsp: /' || true

# 6. smoke: profile must actually generate before the driver adopts it
SMOKE_MODEL="${LOOP_SMOKE_MODEL:-qwen3-coder:30b}"
# v6.49: defaut aligne sur le nom REELLEMENT charge par le driver (etait le nom
# lmstudio-community, different -> smoke sur un nom inexistant -> faux echec de profil).
[ "${LOOP_MLX:-0}" = 1 ] && SMOKE_MODEL="${LOOP_MLX_MODEL:-qwen3-coder-30b-a3b-instruct-mlx}"
OUT="$(HERMES_HOME="$PROFILE" LOOP_REPO_ROOT="$WT" timeout 120 hermes -m "$SMOKE_MODEL" -t file -z "Reply with exactly: PONG" --cli 2>&1 | tail -3)"
if printf '%s' "$OUT" | grep -q "PONG"; then
  echo "[profile] smoke OK, profile ready at $PROFILE"
  exit 0
else
  echo "[profile] SMOKE FAILED, driver must fall back to the user profile. Output tail:"
  printf '%s\n' "$OUT" | tail -2
  exit 1
fi
