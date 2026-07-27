#!/usr/bin/env bash
# auto-skill-scoring (v5.7.3): tally which injected-skill idioms actually appear in
# this run's GREEN diffs. Cumulative in loop/skills/scores.tsv. The ritual prunes
# skills whose hits stay ~0 (not helping) and trusts high-hit ones.
# Usage: score-skills.sh <BASE-branch>   (run from the worktree)
set -uo pipefail
BASE="${1:-dev}"
SCORES="loop/skills/scores.tsv"
DIFF="$(git diff "$BASE"..HEAD 2>/dev/null)"
[ -z "$DIFF" ] && { echo "[skills] no greens this run, nothing to score"; exit 0; }
python3 - "$SCORES" <<PY
import os,sys,datetime
scores=sys.argv[1]
diff='''$DIFF'''
sig={
 "10-spring-boot-3":["@Service","record ","@Getter","NoSuchElementException"],
 "20-angular-21":["signal(","inject(","standalone","@if","@for"],
 "01-project-conventions":["NoSuchElementException","BigDecimal","IllegalArgumentException"],
 "02-project-ui-tokens":["brand-color","material-symbols","font-display","app-sidebar"],
 "00-engineering-discipline":["repository.save",".save(","saveAll"],
}
cum={}
if os.path.exists(scores):
    for ln in open(scores):
        p=ln.rstrip("\n").split("\t")
        if len(p)>=2 and p[1].isdigit(): cum[p[0]]=int(p[1])
run=datetime.date.today().isoformat()
rows=[]
for sk,pats in sig.items():
    hits=sum(diff.count(x) for x in pats)
    cum[sk]=cum.get(sk,0)+hits
    rows.append((sk,cum[sk],hits))
with open(scores,"w") as f:
    f.write("skill\tcumulative\tthis_run\tlast\n")
    for sk,c,h in sorted(rows,key=lambda r:-r[1]):
        f.write(f"{sk}\t{c}\t{h}\t{run}\n")
print("[skills] scored:", ", ".join(f"{sk}+{h}" for sk,c,h in rows if h))
PY
