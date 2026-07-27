#!/usr/bin/env bash
# v6.8 pre_verify: les PROBE de la carte tournent DANS le tour du maker, avant qu'il
# ne conclue. Echec => {"action":"continue","message":...} et le maker corrige avec le
# contexte encore chaud, au lieu de payer un cycle RED complet (gate, bank, revert,
# retry). Le gate bash reste le juge FINAL, ce hook n'est qu'une avance de decouverte.
# Contrat hermes (v0.18): payload JSON sur stdin (coding, attempt, ...); toute sortie
# autre que continue/block laisse le tour se terminer. max_verify_nudges=3 borne dur.
set -u
[ "${LOOP_PREVERIFY:-1}" = "1" ] || exit 0
[ -n "${LOOP_CARD:-}" ] && [ -f "${LOOP_CARD:-}" ] && [ -n "${LOOP_REPO_ROOT:-}" ] || exit 0
# le heredoc python consomme stdin: capturer le payload AVANT et le passer par env
HERMES_PAYLOAD="$(cat 2>/dev/null || true)"
export HERMES_PAYLOAD
exec python3 - "$LOOP_CARD" "$LOOP_REPO_ROOT" <<'PY'
import json, os, re, subprocess, sys

card, root = sys.argv[1], sys.argv[2]
try:
    payload = json.loads(os.environ.get("HERMES_PAYLOAD") or "{}")
except Exception:
    payload = {}
# uniquement les tours de code; auto-throttle: 2 relances max par tour (borne dure hermes: 3)
if not payload.get("coding", True) or int(payload.get("attempt") or 0) >= 2:
    sys.exit(0)

text = open(card, encoding="utf-8", errors="replace").read()
# format canonique du driver: "PROBE: <cmd>"
probes = [p.strip() for p in re.findall(r"^PROBE:\s*(.+)$", text, re.M)]
# format liste des cartes reecrites: en-tete "PROBE" puis "- `cmd`" (une ligne PURE backticks;
# une ligne avec de la prose apres les backticks porte une semantique humaine, on la saute)
m = re.search(r"^PROBE\s*$(.*?)(?=^[A-Z#]|\Z)", text, re.M | re.S)
if m:
    for item in re.findall(r"^-\s*(.+)$", m.group(1), re.M):
        item = item.strip()
        b = re.fullmatch(r"`([^`]+)`", item)
        if b:
            probes.append(b.group(1).strip())

fails = []
for cmd in probes:
    if not cmd:
        continue
    try:
        r = subprocess.run(["bash", "-lc", cmd], cwd=root, capture_output=True,
                           text=True, timeout=300)
    except subprocess.TimeoutExpired:
        fails.append((cmd, "TIMEOUT apres 300s"))
        continue
    if r.returncode != 0:
        tail = "\n".join(((r.stdout or "") + "\n" + (r.stderr or "")).strip().splitlines()[-25:])
        fails.append((cmd, tail[:3000]))

# trace d'observabilite: une ligne par invocation (preuve que le hook vit)
try:
    import datetime, pathlib
    lg = pathlib.Path(root) / "loop" / "logs" / "preverify.log"
    lg.parent.mkdir(parents=True, exist_ok=True)
    with open(lg, "a") as f:
        f.write("%s %s attempt=%s probes=%d fails=%d\n" % (
            datetime.datetime.now().strftime("%F %T"),
            card.rsplit("/", 1)[-1], payload.get("attempt", 0), len(probes), len(fails)))
except Exception:
    pass

if fails:
    msg = ["VERIFICATION AVANT CONCLUSION: %d PROBE de la carte echouent encore." % len(fails)]
    for cmd, tail in fails[:3]:
        msg.append("\n$ %s\n%s" % (cmd, tail))
    msg.append("\nCorrige puis re-verifie toi-meme avant de conclure. Ne conclus pas avec un PROBE rouge.")
    print(json.dumps({"action": "continue", "message": "\n".join(msg)[:8000]}))
sys.exit(0)
PY
