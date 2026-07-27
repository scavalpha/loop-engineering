#!/usr/bin/env bash
# v6.17 CAPTEUR DE FIDELITE MAQUETTE (oeil mecanique, pas un gate: la fidelite est
# adjacente au gout, le veto humain du matin reste juge). Pour chaque ecran de la
# maquette apparie a une page construite, compare une SIGNATURE STRUCTURELLE (boutons,
# champs, colonnes de tableau, titres, liens de nav) entre le HTML maquette et le
# template Angular. Ecart marque => le cartographe emet une carte de mise en conformite.
# Sortie: docs/maquette-fidelity.md + lignes ECART sur stdout pour le cartographe.
# Limite v1 assumee: signature du template de la page SEULE, pas de ses composants enfants;
# un p0 peut donc surestimer l'ecart si la page delegue a des sous-composants. Le signal
# reste directionnel (un ecran maquette riche face a une page vide = vrai ecart), et le
# cartographe/humain tranche. v2: suivre les selecteurs de composants references.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"; cd "$ROOT"
BACK_DIR="${BACK_DIR:-backend}"; FRONT_DIR="${FRONT_DIR:-frontend}"
MAQ_DIR="${MAQ_DIR:-design/screens}"; PAGES_DIR="${PAGES_DIR:-frontend/src/app/pages}"
[ -f loop/stack.sh ] && . loop/stack.sh 2>/dev/null

sig(){ # signature structurelle d'un ou plusieurs fichiers html: b=boutons i=champs c=cols t=titres n=nav
  local files="$1" b i c t n
  b=$(grep -rhoiE '<button|mat-button|\(click\)' $files 2>/dev/null | wc -l | tr -d ' ')
  i=$(grep -rhoiE '<input|<textarea|<select|matInput|formControlName' $files 2>/dev/null | wc -l | tr -d ' ')
  c=$(grep -rhoiE '<th|matColumnDef|<td' $files 2>/dev/null | wc -l | tr -d ' ')
  t=$(grep -rhoiE '<h1|<h2|<h3|mat-card-title' $files 2>/dev/null | wc -l | tr -d ' ')
  n=$(grep -rhoiE 'routerLink|<a ' $files 2>/dev/null | wc -l | tr -d ' ')
  echo "$b $i $c $t $n"
}

slug(){ echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9'; }

{ echo "# Fidelite maquette vs pages construites, $(date '+%F %H:%M')"
  echo "# oeil mecanique v1: signature structurelle (boutons/champs/colonnes/titres/nav)."
  echo "# ecart = |maquette - page| relatif > 40% sur un axe structurel majeur."
  echo
  echo "| Ecran maquette | Page | boutons m/p | champs m/p | cols m/p | titres m/p | verdict |"
  echo "|---|---|---|---|---|---|---|"; } > /tmp/$(basename "$ROOT")-maqfid.md

ECARTS=""
for maq in "$MAQ_DIR"/*.html; do
  [ -f "$maq" ] || continue
  mname="$(basename "$maq" .html)"; ms="$(slug "$mname")"
  # apparier a une page dont le slug recouvre celui de l'ecran (items-list -> items)
  page=""; for p in "$PAGES_DIR"/*/; do
    [ -d "$p" ] || continue; ps="$(slug "$(basename "$p")")"
    case "$ms" in *"$ps"*|"$ps"*) [ ${#ps} -ge 4 ] && page="$p" && break ;; esac
    case "$ps" in *"$ms"*) [ ${#ms} -ge 4 ] && page="$p" && break ;; esac
  done
  if [ -z "$page" ]; then
    echo "| $mname | (AUCUNE) | - | - | - | - | ECRAN NON CONSTRUIT |" >> /tmp/$(basename "$ROOT")-maqfid.md
    ECARTS="$ECARTS
ECART maquette: l'ecran '$mname' de la maquette n'a pas de page construite."
    continue
  fi
  read mb mi mc mt mn <<< "$(sig "$maq")"
  read pb pi pc pt pn <<< "$(sig "$page*.html")"
  verdict="conforme"; gap=""
  for pair in "boutons:$mb:$pb" "champs:$mi:$pi" "colonnes:$mc:$pc"; do
    axe="${pair%%:*}"; m="${pair#*:}"; mm="${m%%:*}"; pp="${m##*:}"
    hi=$(( mm > pp ? mm : pp )); lo=$(( mm < pp ? mm : pp ))
    [ "$hi" -ge 3 ] && [ "$(( (hi-lo)*100 / hi ))" -gt 40 ] && { verdict="ECART"; gap="$gap $axe(m$mm/p$pp)"; }
  done
  echo "| $mname | $(basename "$page") | $mb/$pb | $mi/$pi | $mc/$pc | $mt/$pt | $verdict$gap |" >> /tmp/$(basename "$ROOT")-maqfid.md
  [ "$verdict" = "ECART" ] && ECARTS="$ECARTS
ECART maquette: '$mname' vs page $(basename "$page") diverge structurellement:$gap (mettre en conformite avec $maq)."
done

mkdir -p docs; cp /tmp/$(basename "$ROOT")-maqfid.md docs/maquette-fidelity.md
git add docs/maquette-fidelity.md 2>/dev/null
printf '%s\n' "$ECARTS" | grep -v '^$' || true
