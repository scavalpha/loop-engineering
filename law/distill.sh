#!/usr/bin/env bash
# v5.9 DISTILLER, the learning arc. Turns one run's experience into updated artifacts so
# the NEXT run starts smarter (Voyager principle: a growing library, not a retry machine).
#   AUTO tier   : skill files (both stores), new hints.d entries, skills/retired/,
#                 scores history, loop/state/metrics.tsv. Committed as "distill: run <id>".
#   PROPOSE tier: card rewrites + 92-harness meta-cards under loop/proposals/<date>/,
#                 inert until a human applies them in the morning review.
#   LAW tier    : run-cycle.sh / loop-overnight.sh / verify.sh / constitution.md / tests
#                 are NEVER touched here, by construction (path allowlist below).
# Usage: distill.sh [report.md]     (defaults to the latest report; safe to re-run)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BASE="${LOOP_BASE:-dev}"
STACK_NAME="angular-spring"; [ -f loop/stack.sh ] && . loop/stack.sh 2>/dev/null
GENERAL_SKILLS="${LOOP_GENERAL_SKILLS:-$HOME/dev/loop-skills-general}"
# v6.45 (BUG B pilote): GSTORE etait defini ligne ~325 mais utilise ligne ~128
# (maker-perf-cross) -> unbound variable sous set -u, distill mort. Classe def-avant-
# usage, 4e recidive (version variable). Defini ICI, en tete, une seule fois.
GSTORE="${LOOP_SKILLS_STORE:-$HOME/dev/loop-skills-general}"
REPORT="${1:-$(ls -t loop/reports/report-*.md 2>/dev/null | head -1)}"
[ -n "$REPORT" ] && [ -f "$REPORT" ] || { echo "[distill] no report, nothing to distill"; exit 0; }
RUN_ID="$(basename "$REPORT" .md | sed 's/^report-//')"
PROP="loop/proposals/$(date +%Y%m%d)"
mkdir -p loop/state loop/hints.d loop/skills/retired "$PROP"

# ---------- 1. metrics (pure bash, the honesty curve) ----------
# report lines: "- <name>: GREEN <sha>, <DUR>m, ..." ; failures: "- <name>: <reason>..."
GREENS_N="$(grep -cE '^- .*: GREEN ' "$REPORT" 2>/dev/null || true)"
DURS="$(grep -oE ': GREEN [0-9a-f]+, [0-9]+m' "$REPORT" 2>/dev/null | grep -oE '[0-9]+m' | tr -d m)"
BLOCKED_N="$(grep -ciE 'codex-blocked|blocked' "$REPORT" 2>/dev/null || true)"
RED_N="$(grep -ciE 'fast-RED|REDCOMPILE|red compile' "$REPORT" 2>/dev/null || true)"
# hours: run-id is YYYYmmdd-HHMMSS, end = report mtime
START_EPOCH="$(date -j -f "%Y%m%d-%H%M%S" "$RUN_ID" +%s 2>/dev/null || echo "")"
END_EPOCH="$(stat -f %m "$REPORT" 2>/dev/null || date +%s)"
HOURS="0"
[ -n "$START_EPOCH" ] && HOURS="$(python3 -c "print(round((${END_EPOCH}-${START_EPOCH})/3600,2))" 2>/dev/null || echo 0)"
GPH="$(python3 -c "h=float('$HOURS' or 0); g=int('${GREENS_N:-0}' or 0); print(round(g/h,2) if h>0.05 else 0)" 2>/dev/null || echo 0)"
MED="na"
[ -n "$DURS" ] && MED="$(printf '%s\n' $DURS | sort -n | awk '{a[NR]=$1} END{print (NR%2? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2)}')"
MET="loop/reports/metrics.tsv"
[ -f "$MET" ] || printf 'run\thours\tgreens\tgreens_per_hour\tmedian_min_to_green\tblocked\tred\n' > "$MET"
# v6.6 KPI d'autonomie: patches de LOI par des humains depuis le dernier run.
# La perfection sans humain exige que cette colonne tende vers zero.
LAW_P="$(git log --format=%s "$BASE"..HEAD -- 'loop/*.sh' 'loop/tests/*.sh' 2>/dev/null | grep -vc '\[loop\]' || true)"
grep -q 'law_patches' "$MET" 2>/dev/null || python3 - "$MET" <<'PYH'
import sys
p = sys.argv[1]; L = open(p).read().split('\n')
if L and L[0].startswith('run\t') and 'law_patches' not in L[0]:
    L[0] += '\tlaw_patches'; open(p, 'w').write('\n'.join(L))
PYH
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$RUN_ID" "$HOURS" "${GREENS_N:-0}" "$GPH" "$MED" "${BLOCKED_N:-0}" "${RED_N:-0}" "${LAW_P:-0}" >> "$MET"
echo "[distill] loi: ${LAW_P:-0} patch(es) humain(s) ce run (cible: 0)"
echo "[distill] metrics: greens=${GREENS_N:-0} in ${HOURS}h => $GPH/h (median ${MED}m to green)"
# trend line for the report reader
TREND="$(tail -n +2 "$MET" | awk -F'\t' '{printf "%s:%s ", $1, $4}' | tail -c 200)"
echo "[distill] greens/hour trend: $TREND"

# ---------- 2. score consumption (pure bash+python, closes the write-only loop) ----------
SCORES="loop/skills/scores.tsv"
HIST="loop/skills/scores-history.tsv"
if [ -f "$SCORES" ]; then
  TODAY="$(date +%F)"
  tail -n +2 "$SCORES" | while IFS=$'\t' read -r sk cum this last; do
    printf '%s\t%s\t%s\n' "$TODAY" "$sk" "$cum" >> "$HIST"
  done
  # retire: a skill present on >=2 distinct dates with cumulative still <3 is not helping.
  python3 - "$HIST" <<'PY'
import sys, collections
hist = sys.argv[1]
dates = collections.defaultdict(set); last = {}
for ln in open(hist):
    p = ln.rstrip("\n").split("\t")
    if len(p) >= 3 and p[2].isdigit():
        dates[p[1]].add(p[0]); last[p[1]] = int(p[2])
for sk, ds in dates.items():
    if len(ds) >= 2 and last.get(sk, 99) < 3:
        print(sk)
PY
fi | while IFS= read -r RETIRE; do
  [ -n "$RETIRE" ] || continue
  for store in loop/skills "$GENERAL_SKILLS"; do
    f="$(ls "$store"/*"$RETIRE"* 2>/dev/null | head -1)"
    if [ -n "$f" ] && [ -f "$f" ]; then
      mkdir -p loop/skills/retired
      mv "$f" "loop/skills/retired/$(basename "$f")"
      echo "[distill] retired low-scoring skill: $(basename "$f") (cumulative <3 after 2+ nights)"
      echo "- $(date +%F): retired $(basename "$f") (score <3 after 2+ nights)" >> loop/skills/INDEX.md
    fi
  done
done

# ---------- 2b. score du CARTOGRAPHE (v6.5): le destin des cartes 50- est objectif ----------
# verte = bonne detection, AUTODONE immediat = ecart fantome, morte/final-fail = bruit.
FBDIG="$(ls -t loop/feedback/archive-*.md 2>/dev/null | head -2 | xargs grep -h '^ITEM:\|^TYPE:' 2>/dev/null | head -20 | tr '\n' ' ')"
[ -z "$FBDIG" ] && FBDIG="(aucun)"
HANDSEED="$(git log --diff-filter=A --name-only --format= "$BASE"..HEAD -- 'loop/tasks/*.md' 2>/dev/null | grep -v '^loop/tasks/50-' | grep -vE '(01-)?40-' | grep -v '^$' | sort -u | head -5 | tr '\n' ' ')"
[ -z "$HANDSEED" ] && HANDSEED="(aucune)"
C_GEN="$(git log --format=%s "$BASE"..HEAD 2>/dev/null | grep -c 'carto: ' || true)"
C_GREEN="$(git log --format=%s "$BASE"..HEAD 2>/dev/null | grep -cE '^feat: 50-' || true)"
C_DEAD="$(ls loop/state/failed/50-*.md loop/state/failed/*-50-*.md 2>/dev/null | wc -l | tr -d ' ')"
if ls loop/tasks/50-*.md >/dev/null 2>&1 || [ "${C_GREEN:-0}" -gt 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$RUN_ID" "${C_GREEN:-0}" "${C_DEAD:-0}" "$(ls loop/tasks/50-*.md 2>/dev/null | wc -l | tr -d ' ')" >> loop/reports/carto-score.tsv
fi
# v6.6: destin des cartes nees du FEEDBACK humain (40-): taux de conversion de ses mots en verts
F_GREEN="$(git log --format=%s "$BASE"..HEAD 2>/dev/null | grep -cE '^feat: (01-)?40-' || true)"
F_DEAD="$(ls loop/state/failed/40-*.md loop/state/failed/*-40-*.md 2>/dev/null | wc -l | tr -d ' ')"
if ls loop/tasks/40-*.md loop/tasks/01-40-*.md >/dev/null 2>&1 || [ "${F_GREEN:-0}" -gt 0 ]; then
  printf '%s\t%s\t%s\t%s\n' "$RUN_ID" "${F_GREEN:-0}" "${F_DEAD:-0}" "$(ls loop/tasks/40-*.md loop/tasks/01-40-*.md 2>/dev/null | wc -l | tr -d ' ')" >> loop/reports/feedback-score.tsv
  echo "[distill] feedback-score: verts=${F_GREEN:-0} morts=${F_DEAD:-0}"
fi
echo "[distill] carto-score: verts=${C_GREEN:-0} morts=${C_DEAD:-0} (precision de detection tracee)"

# v6.19: debit du maker par famille (le "codex 3x plus rapide qu'opus" devient mesure).
PERF="loop/reports/maker-perf.tsv"
if [ -s "$PERF" ]; then
  python3 - "$PERF" "$RUN_ID" >> "$REPORT" 2>/dev/null <<'PYPERF'
import sys, collections, statistics
rows = [l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
g = collections.defaultdict(list)
for r in rows:
    if len(r) >= 6 and r[5] == "GREEN":
        spec = r[6] if len(r) >= 7 else "spec=?"
        try: g[r[2] + " " + spec].append(int(r[4]))
        except: pass
if g:
    print("- DEBIT MAKER (mediane s/vert par famille, spec=0 sans / spec=1 avec speculatif):")
    for k in sorted(g, key=lambda k: statistics.median(g[k])):
        print("  - %s: %ds/vert (n=%d)" % (k, int(statistics.median(g[k])), len(g[k])))
PYPERF
  # remontee cross-loop: le store agrege les deux projets (colonne slug projet)
  if [ -d "$GSTORE" ]; then
    _PS="$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
    awk -v p="$_PS" -F'\t' 'NF>=6{print p"\t"$0}' "$PERF" >> "$GSTORE/maker-perf-cross.tsv" 2>/dev/null
    sort -u "$GSTORE/maker-perf-cross.tsv" -o "$GSTORE/maker-perf-cross.tsv" 2>/dev/null
  fi
fi

# ---------- 3. distillation proposals (one codex read-only call, parsed defensively) ----------
if command -v codex >/dev/null 2>&1 && [ "${LOOP_DISTILL_MODEL:-codex}" != "off" ]; then
  LESSONS_CARDS="$(grep -l '## LESSONS' loop/tasks/*.md 2>/dev/null | head -5)"
  LESSONS_TXT=""
  for lc in $LESSONS_CARDS; do LESSONS_TXT="$LESSONS_TXT
--- $lc ---
$(sed -n '/## LESSONS/,$p' "$lc" | head -40)"; done
  GREENLOG="$(git log --format='%s' --stat "$BASE"..HEAD 2>/dev/null | head -80)"
  DP="You are the post-run DISTILLER of an autonomous coding loop (local maker builds task
cards, codex reviews, bash gate commits/reverts). Read this run's evidence and distill it
into artifact updates so the NEXT run performs better. Evidence:

## RUN REPORT
$(cat "$REPORT")

## GREEN COMMITS (what worked)
$GREENLOG

## LESSONS ON FAILED CARDS (what kept failing)
$LESSONS_TXT

## CURRENT SKILLS (project tier)
$(head -30 loop/skills/*.md 2>/dev/null | head -80)

## CURRENT HINTS (compile-repair patterns already known)
$(ls loop/hints.d/ 2>/dev/null)

## RESIDUAL LOT FINDINGS (survived 2 fix generations, MUST be resolved via card rewrites)
$(cat "loop/proposals/$(date +%Y%m%d)"/lot-*-residual-findings.txt 2>/dev/null | head -c 4000)

Beyond per-card fixes, analyse ACROSS the run STRUCTURALLY (card geometry):
- SEAMS: two cards that blocked on each other's missing pieces (one needed an endpoint or
  service the other builds) are ONE use case artificially split. Propose a MERGED card
  (largest card with a SINGLE user-nameable goal beats micro-splits; splits create
  integration seams and fake blocks).
- PROBE-GAP lines in the report mean that card's probes all passed while the reviewer
  rejected it: the probes under-encode the DONE WHEN. Propose a CARD-REWRITE whose PROBEs
  mechanically encode EVERY DONE WHEN criterion (one probe per criterion), because the
  maker self-checks probes but prose criteria fade. PROBE lines are RAW shell commands:
  NEVER wrap them in markdown backticks or bullets (a backticked probe becomes a bash
  command substitution and fails forever; proven 2026-07-10, 3 false reds).
- If a geometry lesson generalises, capture it in the card-design skill
  (loop/skills/05-card-design.md) via SKILL-UPDATE.
- DETECTION: feedback humain recent (dispositions): $FBDIG
  Chaque item de TYPE BUG ou SYMPTOME est un CAPTEUR MANQUANT: l'humain a vu ce que les
  yeux mecaniques n'ont pas vu. Emets la lentille ===CARTO-LENS=== correspondante.
- DETECTION: cartes seedees A LA MAIN (hors cartographe) depuis le dernier run: $HANDSEED
  Chacune est une detection MANQUEE: l'humain a vu un ecart avant le cartographe.
  Emets la lentille ===CARTO-LENS=== qui l'aurait generee automatiquement.
- DETECTION: si un constat HUMAIN (NIGHT-BRIEF) ou un finding de lot revele un ecart
  que le cartographe aurait du voir, emets ===CARTO-LENS=== avec UNE nouvelle lentille
  (une ligne, format des lentilles existantes). Si une carte 50- etait un ecart fantome
  (AUTODONE immediat), emets une lentille de PRECISION qui evite ce faux positif.
- RESIDUAL LOT FINDINGS are findings that survived 2 runtime fix attempts: runtime retry
  is the WRONG tool for them. For EACH card a residual finding touches, emit a
  CARD-REWRITE that bakes the finding into the card itself: state the required behaviour
  in the USE CASE, add it to DONE WHEN, and add a PROBE that mechanically asserts it.
  The next build then satisfies it by construction. Never leave a residual unconverted.

Emit ONLY fenced blocks in EXACTLY these formats (no prose outside blocks). Every block
optional; emit only what the evidence supports. Max 2 SKILL-UPDATE, max 2 NEW-HINT.
For a merge, emit a CARD-REWRITE named for the FIRST card whose body is the merged use
case, plus (in the same block's final line) 'RETIRES: <second-card-basename>'.

===SKILL-UPDATE <loop/skills/NN-name.md>===
TIER: universel|stack|projet   (universel = procedure valable sur tout stack; stack = idiome Angular/Spring; projet = convention propre au projet)
<the COMPLETE new file content: short, imperative idioms proven by this run's greens; keep
under 25 lines>
===END===

===NEW-HINT <kebab-slug>===
MATCH: <egrep regex matching a compile-error class seen 2+ times this run>
---
<3-6 line actionable repair instruction for the maker>
===END===

===CARD-REWRITE <card-basename-without-.md>===
<a full rewritten use-case card for a card that failed 2+ cycles this run: USE CASE /
CONTEXT / DONE WHEN / SCOPE / PROBE format>
===END===

===CARTO-LENS===
- <NOM>: <une ligne, la nouvelle lentille de detection>
===END===

===META-CARD <kebab-slug>===
<a 92-harness meta-card PROPOSING a harness improvement a human should review, with the
evidence line references>
===END==="
  DOUT="$(timeout 300 codex exec --sandbox read-only --skip-git-repo-check -c model_reasoning_effort=low "$DP" 2>/dev/null || true)"
  if [ -n "$DOUT" ]; then
    printf '%s\n' "$DOUT" > "$PROP/distiller-raw-$RUN_ID.txt"
    # apply SKILL-UPDATE blocks (allowlist: the two skill stores; cap 2; cap 4KB)
    printf '%s\n' "$DOUT" | awk '/^===SKILL-UPDATE /{p=$0; sub(/^===SKILL-UPDATE /,"",p); sub(/===$/,"",p); f="/tmp/distill-skill-" ++n ".block"; print p > f".path"; inb=1; next} /^===END===$/{inb=0; close(f); next} inb{print >> f}' 2>/dev/null
    for i in 1 2; do
      B="/tmp/distill-skill-$i.block"; P="/tmp/distill-skill-$i.block.path"
      [ -f "$B" ] && [ -f "$P" ] || continue
      TARGET="$(cat "$P" | tr -d '[:space:]')"
      case "$TARGET" in
        loop/skills/*.md) DEST="$TARGET" ;;
        *) DEST="" ;;
      esac
      if [ -n "$DEST" ] && [ "$(wc -c < "$B")" -lt 4096 ]; then
        cp "$B" "$DEST"
        echo "[distill] skill updated: $DEST"
      fi
      rm -f "$B" "$P"
    done
    # apply NEW-HINT blocks (validate the MATCH regex compiles; cap 2)
    printf '%s\n' "$DOUT" | awk '/^===NEW-HINT /{p=$0; sub(/^===NEW-HINT /,"",p); sub(/===$/,"",p); f="/tmp/distill-hint-" ++n ".block"; print p > f".name"; inb=1; next} /^===END===$/{inb=0; close(f); next} inb{print >> f}' 2>/dev/null
    for i in 1 2; do
      B="/tmp/distill-hint-$i.block"; N="/tmp/distill-hint-$i.block.name"
      [ -f "$B" ] && [ -f "$N" ] || continue
      SLUG="$(cat "$N" | tr -cd 'a-z0-9-' | head -c 40)"
      RX="$(sed -n 's/^MATCH:[[:space:]]*//p' "$B" | head -1)"
      RXOK=0
      if [ -n "$RX" ]; then
        printf '' | grep -qE "$RX" 2>/dev/null; [ $? -ne 2 ] && RXOK=1   # rc 2 = invalid regex
      fi
      if [ -n "$SLUG" ] && [ "$RXOK" = 1 ]; then
        [ -f "loop/hints.d/90-$SLUG.hint" ] || { cp "$B" "loop/hints.d/90-$SLUG.hint"; echo "[distill] new hint: 90-$SLUG.hint"; }
      fi
      rm -f "$B" "$N"
    done
    # CARTO-LENS -> append aux lentilles (donnees, auto, cap 2)
    printf '%s\n' "$DOUT" | awk '/^===CARTO-LENS===$/{f=1;next} /^===END===$/{f=0} f' | grep '^- ' | head -2 | while IFS= read -r L; do
      grep -qF -- "$L" loop/carto-lenses.md 2>/dev/null || { printf '%s\n' "$L" >> loop/carto-lenses.md; echo "[distill] nouvelle lentille carto: $L"; }
    done
    git add loop/carto-lenses.md 2>/dev/null
    # CARD-REWRITE + META-CARD -> written to proposals/ first
    printf '%s\n' "$DOUT" | awk -v d="$PROP" '/^===CARD-REWRITE /{p=$0; sub(/^===CARD-REWRITE /,"",p); sub(/===$/,"",p); gsub(/[^a-zA-Z0-9_-]/,"",p); f=d "/card-rewrite-" p ".md"; inb=1; next} /^===META-CARD /{p=$0; sub(/^===META-CARD /,"",p); sub(/===$/,"",p); gsub(/[^a-zA-Z0-9_-]/,"",p); f=d "/92-harness-" p ".md"; inb=1; next} /^===END===$/{inb=0; close(f); next} inb{print >> f}'
    # v5.9.1 SELF-APPLY (user directive: "the loop should improve itself, apply its own
    # proposal"). A GRADER pass (independent codex call) scores each CARD-REWRITE 1-10 on:
    # preserves the card's domain intent, use-case format, has DONE WHEN + PROBEs, not
    # weaker than the current card. Grade >=7 => auto-applied to loop/tasks/ (DEPENDS
    # lines from the current card are preserved). Grade <7 => stays a proposal for the
    # morning. META-CARDS (harness law changes) are NEVER auto-applied: law tier stays
    # human-signed (the DGM lesson: self-modification needs empirical gating).
    for CR in "$PROP"/card-rewrite-*.md; do
      [ -f "$CR" ] || continue
      CB="$(basename "$CR" .md | sed 's/^card-rewrite-//')"
      TGT="loop/tasks/$CB.md"
      [ -f "$TGT" ] || { echo "[distill] rewrite $CB: no such card, left as proposal"; continue; }
      GRADE="$(timeout 120 codex exec --sandbox read-only --skip-git-repo-check -c model_reasoning_effort=low \
        "Grade this REWRITTEN task card 1-10 for an autonomous coding loop. 10 = clearly better than the CURRENT card: keeps the same domain intent, use-case format (USE CASE/CONTEXT/DONE WHEN/SCOPE/PROBE), behavioral probes, and fixes the failure the rewrite targets. 1 = loses intent or weakens acceptance. Reply with ONLY the integer.

## CURRENT CARD
$(cat "$TGT")

## REWRITTEN CARD
$(cat "$CR")" 2>/dev/null | grep -oE '^[0-9]+$|[0-9]+' | head -1)"
      if [ -n "$GRADE" ] && [ "$GRADE" -ge 7 ] 2>/dev/null; then
        DEPLINE="$(grep '^DEPENDS:' "$TGT" 2>/dev/null | head -1)"
        cp "$CR" "$TGT"
        [ -n "$DEPLINE" ] && ! grep -q '^DEPENDS:' "$TGT" && printf '%s\n' "$DEPLINE" >> "$TGT"
        # v6.2.10: a rewrite is a RESET event: stale ESCALATED/LESSONS from the old card
        # must not defer-hard the new one to the tail or force the escalation maker
        # (a rewritten 05 sat behind the whole queue on old-era baggage, 2026-07-05)
        python3 - "$TGT" <<'PYIN'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'\n?ESCALATED:.*', '', s)
s = re.split(r'\n## LESSONS', s)[0]
open(p, 'w').write(s)
PYIN
        # v5.9.7 merge support: 'RETIRES: <card>' in an applied rewrite removes the
        # absorbed split card and rewires DEPENDS references to the merged card.
        RET="$(grep -m1 '^RETIRES:' "$TGT" 2>/dev/null | awk '{print $2}')"
        if [ -n "$RET" ] && [ -f "loop/tasks/$RET.md" ]; then
          sed -i '' '/^RETIRES:/d' "$TGT"
          git rm -q "loop/tasks/$RET.md" 2>/dev/null || rm -f "loop/tasks/$RET.md"
          sed -i '' "s/^DEPENDS: $RET/DEPENDS: $CB/" loop/tasks/*.md 2>/dev/null
          echo "[distill] merged: $RET absorbed into $CB (DEPENDS rewired)"
        fi
        echo "[distill] AUTO-APPLIED card rewrite $CB (grade $GRADE/10)"
        echo "- $(date +%F): auto-applied rewrite of $CB (grade $GRADE)" >> loop/skills/INDEX.md
      else
        echo "[distill] rewrite $CB kept as proposal (grade ${GRADE:-unparseable} < 7)"
      fi
    done
    git add loop/tasks 2>/dev/null
    PN="$(ls "$PROP" 2>/dev/null | grep -vc distiller-raw || true)"
    echo "[distill] remaining proposals for morning review: $PN in $PROP/ (meta-cards always human)"
  else
    echo "[distill] codex distillation unavailable, metrics+scores still applied"
  fi
else
  echo "[distill] codex not present or LOOP_DISTILL_MODEL=off, metrics+scores only"
fi

# ---------- 4. commit artifact-tier changes ----------
# v6.9 C2: sync vers le store global (la connaissance monte, les autres loops en heritent)
# (GSTORE defini en tete de fichier depuis v6.45)
# collision inter-projets: meme nom + contenu different => cote a cote suffixe projet,
# jamais d'ecrasement (le cliquet vaut aussi pour la connaissance)
_PSLUG="$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')"
_sync_skill(){ # $1=fichier $2=dossier store
  local dst="$2/$(basename "$1")"
  if [ ! -f "$dst" ]; then cp "$1" "$dst"
  elif ! cmp -s "$1" "$dst"; then cp "$1" "$2/$(basename "$1" .md)-$_PSLUG.md"
  fi
}
if [ -d "$GSTORE" ]; then
  for sk in loop/skills/*.md; do
    [ -f "$sk" ] || continue
    case "$(grep -m1 '^TIER:' "$sk" 2>/dev/null | awk '{print $2}')" in
      universel) _sync_skill "$sk" "$GSTORE/universel" ;;
      stack)     mkdir -p "$GSTORE/stack-${STACK_NAME:-angular-spring}"; _sync_skill "$sk" "$GSTORE/stack-${STACK_NAME:-angular-spring}" ;;
    esac
  done
  # lentilles: FUSION ligne a ligne (deux loops ecrivent le store, jamais d'ecrasement)
  if [ -f loop/carto-lenses.md ]; then
    touch "$GSTORE/lenses-universal.md"
    grep '^- ' loop/carto-lenses.md | while IFS= read -r L; do
      grep -qF -- "$L" "$GSTORE/lenses-universal.md" || printf '%s\n' "$L" >> "$GSTORE/lenses-universal.md"
    done
  fi
fi
git add loop/skills loop/hints.d loop/reports/metrics.tsv "$PROP" 2>/dev/null
git diff --cached --quiet 2>/dev/null || git commit -q -m "distill: run $RUN_ID (greens=${GREENS_N:-0}, $GPH/h, artifacts updated) [loop]" 2>/dev/null
echo "[distill] done"
