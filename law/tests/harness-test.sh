#!/usr/bin/env bash
# Stub-based harness test suite (v5.6, review T5). No models, runs in seconds.
# Real coverage of run-cycle.sh verdict logic (fail-closed, REDCOMPILE, content-hash);
# logic-mirror coverage of driver expressions (tier, commit-name, deadline, DEPENDS).
# Usage: loop/tests/harness-test.sh   (exit 0 = all pass)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); printf '  FAIL %s\n  ---> %s\n' "$1" "$2"; }
eq(){ [ "$2" = "$3" ] && ok "$1" || no "$1" "expected [$3] got [$2]"; }

# ---------- fixture + stubs ----------
make_fixture(){
  # stubs go in $FIX/.local/bin because run-cycle.sh prepends $HOME/.local/bin to PATH;
  # we run it with HOME=$FIX so our stubs shadow the real hermes/codex/npx.
  FIX="$(mktemp -d)"; BIN="$FIX/.local/bin"; mkdir -p "$BIN"
  printf '[user]\n\temail = t@t\n\tname = t\n' > "$FIX/.gitconfig"
  ( cd "$FIX" && HOME="$FIX" git init -q && HOME="$FIX" git add -A 2>/dev/null )
  mkdir -p "$FIX/loop/state" "$FIX/loop/logs" "$FIX/loop/skills" "$FIX/loop/shims" \
           "$FIX/frontend" "$FIX/backend"
  cp "$REPO/loop/run-cycle.sh" "$FIX/loop/"; cp "$REPO/loop/verify.sh" "$FIX/loop/"
  printf 'constitution stub\n' > "$FIX/loop/constitution.md"
  # control files live in the repo root but must be invisible to git status/diff,
  # else run-cycle's "any change?" guard treats them as maker output.
  # Library/ et .cache/: HOME=$FIX fait atterrir les caches macOS/python DANS la racine
  # du fixture; git les voyait comme travail du maker -> faux "arbre modifie" (le checker
  # fail-closed tournait sur un no-change). Prod non concernee: HOME n'est jamais ROOT.
  printf '.local/\n.gitconfig\n.hermes_write\n.ng_exit\n.codex_out\n.codex_calls\ncard.md\ntrace\nloop/logs/\nloop/state/\nLibrary/\n.cache/\n' > "$FIX/.gitignore"
  ( cd "$FIX" && HOME="$FIX" git add -A && HOME="$FIX" git commit -qm init )
  # stub hermes: on call, if .hermes_write=1 create/modify work file (=> git dirty)
  cat > "$BIN/hermes" <<EOF
#!/bin/sh
if [ "\$(cat "$FIX/.hermes_write" 2>/dev/null)" = "1" ]; then
  echo "line \$(date +%s%N)" >> "$FIX/frontend/work.ts"
fi
exit 0
EOF
  # stub npx (ng build): exit code from .ng_exit
  cat > "$BIN/npx" <<EOF
#!/bin/sh
exit \$(cat "$FIX/.ng_exit" 2>/dev/null || echo 0)
EOF
  # stub codex: print .codex_out; also record that it was called
  cat > "$BIN/codex" <<EOF
#!/bin/sh
echo called >> "$FIX/.codex_calls"
cat "$FIX/.codex_out" 2>/dev/null
exit 0
EOF
  chmod +x "$BIN"/*
  echo "0" > "$FIX/.ng_exit"; echo "1" > "$FIX/.hermes_write"; : > "$FIX/.codex_out"; : > "$FIX/.codex_calls"
  printf '# card\nGOAL: x\nSCOPE: front\n' > "$FIX/card.md"
}
run_cycle(){ # runs run-cycle.sh in the fixture; HOME=$FIX so its $HOME/.local/bin stubs win.
  # LOOP_SANDBOX=0: the stub tests exercise verdict logic, not the sandbox wrapper (which
  # would wrap the stub hermes in sandbox-exec and break it). Sandbox is tested separately.
  ( cd "$FIX" && HOME="$FIX" LOOP_SANDBOX=0 LOOP_GENERAL_SKILLS=/nonexistent VERIFY_SCOPE=front \
      TASK_TIMEOUT=15 timeout 60 bash loop/run-cycle.sh "$FIX/card.md" >/dev/null 2>&1 )
}
verdict(){ cat "$FIX/loop/state/verdict.last" 2>/dev/null; }
codex_called(){ [ -s "$FIX/.codex_calls" ] && echo yes || echo no; }

echo "== run-cycle.sh (real, stubbed models) =="

make_fixture; printf 'VERDICT: PASS\nlooks good\n' > "$FIX/.codex_out"; run_cycle
eq "PASS verdict when codex passes"        "$(verdict)" "PASS"
rm -rf "$FIX"

make_fixture; printf 'VERDICT: FAIL\nmissing bits\n' > "$FIX/.codex_out"; run_cycle
eq "FAIL verdict when codex fails"          "$(verdict)" "FAIL"
rm -rf "$FIX"

make_fixture; : > "$FIX/.codex_out"; run_cycle   # codex returns nothing => infra hiccup
eq "fail-closed: no verdict becomes FAIL"   "$(verdict)" "FAIL"
rm -rf "$FIX"

make_fixture; echo "1" > "$FIX/.ng_exit"; printf 'VERDICT: PASS\n' > "$FIX/.codex_out"; run_cycle
eq "REDCOMPILE when build fails both rounds" "$(verdict)" "REDCOMPILE"
eq "checker skipped on REDCOMPILE"           "$(codex_called)" "no"
rm -rf "$FIX"

make_fixture; echo "0" > "$FIX/.hermes_write"; printf 'VERDICT: PASS\n' > "$FIX/.codex_out"; run_cycle
eq "no-change leaves verdict none"          "$(verdict)" "none"
eq "checker skipped on no-change"           "$(codex_called)" "no"
rm -rf "$FIX"

make_fixture; printf 'VERDICT: PASS\n' > "$FIX/.codex_out"; run_cycle
[ -f "$FIX/loop/state/lite.ok" ] && ok "lite.ok written on clean compile" || no "lite.ok written" "missing"
# content-hash sensitivity: marker must change when an UNTRACKED new file's CONTENT
# changes (git status listing + git diff HEAD are both blind to it — the real bug).
th(){ ( cd "$FIX" && HOME="$FIX" bash -c '{ git status --porcelain; git diff HEAD; git ls-files --others --exclude-standard | while IFS= read -r f; do printf ">>%s\n" "$f"; cat "$f"; done; } | shasum -a 256 | cut -d" " -f1' ); }
H1="$(th)"; echo "MORE" >> "$FIX/frontend/work.ts"; H2="$(th)"
[ "$H1" != "$H2" ] && ok "tree_hash changes on untracked-content edit (stale-skip closed)" || no "tree_hash content-sensitive" "hash unchanged"
rm -rf "$FIX"

# v5.7.4: MODIFY-file content must be injected into the maker prompt (the 02b fix)
make_fixture; printf 'VERDICT: PASS\n' > "$FIX/.codex_out"
mkdir -p "$FIX/frontend/src/app"
printf 'export const ROUTES = [ROUTE_ALPHA, ROUTE_BRAVO, ROUTE_CHARLIE];\n' > "$FIX/frontend/src/app/app.routes.ts"
( cd "$FIX" && HOME="$FIX" git add -A && HOME="$FIX" git commit -qm routes )
printf '# card\nGOAL: add a route\nSCOPE: front\nFILES (modify):\n- frontend/src/app/app.routes.ts\n' > "$FIX/card.md"
run_cycle
CYLOG="$(ls -t "$FIX"/loop/logs/cycle-*.log 2>/dev/null | head -1)"
grep -q 'ORIGINAL content of frontend/src/app/app.routes.ts' "$CYLOG" 2>/dev/null && ok "modify-file header injected into prompt" || no "modify injection header" "missing"
grep -q 'ROUTE_ALPHA, ROUTE_BRAVO, ROUTE_CHARLIE' "$CYLOG" 2>/dev/null && ok "modify-file CURRENT content in prompt (maker sees what to preserve)" || no "modify content in prompt" "missing"
rm -rf "$FIX"

echo "== driver logic mirrors (expressions copied from loop-overnight.sh) =="
# commit-name normalization (OV-5): escalated/deferred greens commit under original name
cn(){ local n="$1"; n="${n#00-E-}"; n="${n#zz-D-}"; echo "$n"; }
cn(){ local n="$1"; n="${n#00-E-}"; n="${n#zz-D-}"; n="${n#zz-H-}"; echo "$n"; }
eq "commit-name strips 00-E-"  "$(cn 00-E-02-sidebar-nav)" "02-sidebar-nav"
eq "commit-name strips zz-D-"  "$(cn zz-D-05-item-api)" "05-item-api"
eq "commit-name strips zz-H-"  "$(cn zz-H-06-decision-api)" "06-decision-api"
eq "commit-name plain passes"  "$(cn 11-dashboard-port)"   "11-dashboard-port"

echo "== v5.7.6 phantom-reference mirror =="
phantom(){ printf '%s' "$1" | grep -qiE "find stylesheet|Cannot find module|Could not resolve|NG2008|TS2307" && echo hint || echo none; }
eq "phantom: missing stylesheet -> hint" "$(phantom 'ERROR: Could not find stylesheet file ./x.css')" "hint"
eq "phantom: TS2307 module -> hint"       "$(phantom 'error TS2307: Cannot find module ../models/x')" "hint"
eq "phantom: normal type error -> none"   "$(phantom 'error TS2339: Property filter does not exist')" "none"

echo "== v5.7.2 logic mirrors =="
# convergence gate: continue re-rolling only while findings STRICTLY drop
conv(){ [ "$2" -lt "$1" ] && echo continue || echo stop; }
eq "convergence 5->3 continue" "$(conv 5 3)" "continue"
eq "convergence 3->1 continue" "$(conv 3 1)" "continue"
eq "convergence 2->2 stop"     "$(conv 2 2)" "stop"
eq "convergence 2->3 stop (02b)" "$(conv 2 3)" "stop"
# defer-hard: a card entering with ESCALATED/LESSONS (and not already deferred) defers
HD="$(mktemp -d)"
printf 'GOAL x\n' > "$HD/fresh.md"
printf 'GOAL x\nESCALATED: qwen3-coder:30b\n' > "$HD/esc.md"
printf 'GOAL x\n## LESSONS from a prior night\n' > "$HD/les.md"
hard(){ local name="$1" card="$2"; { [[ "$name" != zz-H-* ]] && [[ "$name" != 00-E-* ]] && grep -qE '^ESCALATED:|^## LESSONS' "$card"; } && echo defer || echo run; }
eq "defer-hard: fresh card runs"        "$(hard 03 "$HD/fresh.md")" "run"
eq "defer-hard: ESCALATED card defers"  "$(hard 03 "$HD/esc.md")"   "defer"
eq "defer-hard: LESSONS card defers"    "$(hard 03 "$HD/les.md")"   "defer"
eq "defer-hard: already-deferred runs"  "$(hard zz-H-03 "$HD/esc.md")" "run"
eq "defer-hard: 00-E- retry runs now"   "$(hard 00-E-03 "$HD/esc.md")" "run"
rm -rf "$HD"

# escalation tier detection (OV-10): 00-E- prefix OR ESCALATED: marker => tier 2
tier(){ local name="$1" card="$2"; { [[ "$name" == 00-E-* ]] || grep -q '^ESCALATED:' "$card" 2>/dev/null; } && echo 2 || echo 1; }
TD="$(mktemp -d)"
printf 'GOAL x\n' > "$TD/plain.md"
printf 'GOAL x\nESCALATED: qwen3-coder:30b\n' > "$TD/esc.md"
printf 'GOAL x\nMAKER: qwen3-coder:30b\n' > "$TD/pin.md"
eq "tier: 00-E- name is tier2"        "$(tier 00-E-05 "$TD/plain.md")" "2"
eq "tier: ESCALATED marker is tier2"  "$(tier 05 "$TD/esc.md")"        "2"
eq "tier: MAKER pin keeps tier1"      "$(tier 05 "$TD/pin.md")"        "1"
rm -rf "$TD"

# deadline math mirror
dl(){ local arg="$1" now=1000000000; local d
  if [[ "$arg" =~ ^\+([0-9]+)h$ ]]; then d=$(( now + ${BASH_REMATCH[1]} * 3600 )); echo $(( d - now ));
  else echo "abs"; fi; }
eq "deadline +2h => 7200s"  "$(dl +2h)" "7200"
eq "deadline +8h => 28800s" "$(dl +8h)" "28800"

# DEPENDS match mirror: green if 'feat: <dep> [loop' present in log
depmet(){ printf '%s\n' "$2" | grep -q "^feat: $1 \[loop" && echo yes || echo no; }
eq "DEPENDS met when green commit exists" "$(depmet 05-item-api 'feat: 05-item-api [loop cycle 3]')" "yes"
eq "DEPENDS unmet when absent"            "$(depmet 05-item-api 'feat: 04-x [loop cycle 1]')"          "no"

# git-shim policy: read-only allowed, stateful/destructive blocked.
# Run inside a THROWAWAY repo so a regressed shim can never touch the real one.
GT="$(mktemp -d)"; ( cd "$GT" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init ) 2>/dev/null
gs(){ ( cd "$GT" && "$REPO/loop/shims/git" "$@" ) >/dev/null 2>&1 && echo allow || echo block; }
eq "git-shim: log allowed"          "$(gs log --oneline -1)"           "allow"
eq "git-shim: show allowed"         "$(gs show --stat HEAD)"           "allow"
eq "git-shim: -C sibling read ok"   "$(gs -C "$GT" log -1)"            "allow"
eq "git-shim: commit blocked"       "$(gs commit -m x)"                "block"
eq "git-shim: push blocked"         "$(gs push origin main)"           "block"
eq "git-shim: reset blocked"        "$(gs reset --hard HEAD)"          "block"
eq "git-shim: clean blocked"        "$(gs clean -fd)"                  "block"
eq "git-shim: add blocked"          "$(gs add .)"                      "block"
eq "git-shim: -c injection blocked" "$(gs -c core.hooksPath=/tmp log)" "block"
rm -rf "$GT"

# maker sandbox profile: OS-enforced fences (fast, deterministic; needs macOS sandbox-exec).
if command -v sandbox-exec >/dev/null 2>&1 && [ -f "$REPO/loop/sandbox/maker.sb" ]; then
  SBW="$(mktemp -d)"; SBLEAK="$HOME/.sbx_leak_test_$$"
  SBX(){ sandbox-exec -D WT="$SBW" -D HH="$HOME/.hermes" -D CACHE="$HOME/Library/Caches" -D DOTCACHE="$HOME/.cache" -f "$REPO/loop/sandbox/maker.sb" "$@"; }
  sbchk(){ SBX sh -c "$1" >/dev/null 2>&1 && echo allow || echo deny; }
  eq "sandbox: write inside worktree ok" "$(sbchk "echo x > $SBW/f")"           "allow"
  eq "sandbox: write to \$HOME denied"   "$(sbchk "echo x > $SBLEAK")"          "deny"
  eq "sandbox: read outside allowed"     "$(sbchk 'cat /etc/hosts')"            "allow"
  rm -rf "$SBW"; rm -f "$SBLEAK"
else
  ok "sandbox: skipped (sandbox-exec or profile absent)"
fi

# fix B: wire_route inserts a child route, preserves existing routes, idempotent.
WR="$(mktemp -d)"; RF="$WR/app.routes.ts"
printf 'export const routes = [\n  { path: %s, children: [\n      { path: %s, loadComponent: () => d, title: %s },\n      { path: %s, redirectTo: %s, pathMatch: %s },\n  ] },\n];\n' "''" "'dashboard'" "'D'" "''" "'dashboard'" "'full'" > "$RF"
wr(){ ROUTE_SPEC="$1" python3 - "$RF" >/dev/null 2>&1 <<'PY'
import os,re,sys
p=[x.strip() for x in os.environ["ROUTE_SPEC"].split("|")]
if len(p)<3: sys.exit(0)
path,imp,cls=p[0],p[1],p[2]; title=p[3] if len(p)>3 else cls
f=sys.argv[1]; src=open(f).read()
if re.search(r"path:\s*'%s'"%re.escape(path),src): sys.exit(0)
b=("      {\n        path: '%s',\n        loadComponent: () =>\n          import('%s').then((m) => m.%s),\n        title: '%s',\n      },\n")%(path,imp,cls,title)
m=re.search(r"\n(\s*)\{\s*path:\s*'',\s*redirectTo:",src)
if not m: sys.exit(1)
i=m.start()+1; open(f,"w").write(src[:i]+b+src[i:])
PY
}
wr "file-validation | ./p/fv | FileValidation | FV"
eq "wire_route: new route inserted"  "$(grep -c "path: 'file-validation'" "$RF")" "1"
eq "wire_route: existing route kept" "$(grep -c "path: 'dashboard'" "$RF")"       "1"
eq "wire_route: redirect kept"       "$(grep -c "redirectTo: 'dashboard'" "$RF")" "1"
wr "file-validation | ./p/fv | FileValidation | FV"
eq "wire_route: idempotent (no dup)" "$(grep -c "path: 'file-validation'" "$RF")" "1"
rm -rf "$WR"

# fix B: clean_junk strips maker junk (root verify scripts + summaries + src .md), keeps code
CJ="$(mktemp -d)"; ( cd "$CJ" && git init -q && mkdir -p f/src/app/x \
  && echo x > hermes-verify-file-validation.ts && echo x > verification-summary.md \
  && echo x > f/src/app/x/IMPLEMENTATION_SUMMARY.md \
  && echo 'export const a=1' > f/src/app/x/a.ts && echo 'export const c=3' > f/src/app/x/check-status.ts )
( cd "$CJ"
  git ls-files --others --exclude-standard 2>/dev/null | grep -iE '(^|/)hermes-verify[^/]*|(^|/)[^/]*(implementation_summary|verification-summary|[-_]summary|[-_]notes|scratch|diagnostic)\.(md|txt|ts|js)$|(^|/)verify[^/]*\.(sh|mjs|cjs)$' | while IFS= read -r j; do rm -f "$CJ/$j"; done
  git ls-files --others --exclude-standard f/src 2>/dev/null | grep -iE '\.md$' | while IFS= read -r j; do rm -f "$CJ/$j"; done )
eq "clean_junk: root verify script gone" "$([ -f "$CJ/hermes-verify-file-validation.ts" ] && echo yes || echo no)" "no"
eq "clean_junk: root summary gone"        "$([ -f "$CJ/verification-summary.md" ] && echo yes || echo no)"          "no"
eq "clean_junk: src junk .md gone"        "$([ -f "$CJ/f/src/app/x/IMPLEMENTATION_SUMMARY.md" ] && echo yes || echo no)" "no"
eq "clean_junk: code .ts kept"            "$([ -f "$CJ/f/src/app/x/a.ts" ] && echo yes || echo no)"                 "yes"
eq "clean_junk: legit check-status kept"  "$([ -f "$CJ/f/src/app/x/check-status.ts" ] && echo yes || echo no)"      "yes"
rm -rf "$CJ"

# fix A: escalation retry (zz-E-) sorts after fresh cards, before zz-H-
eq "fast-defer: fresh before zz-E" "$(printf '02b\nzz-E-02b\n' | sort | head -1)"  "02b"
eq "fast-defer: zz-E before zz-H"  "$(printf 'zz-E-x\nzz-H-x\n' | sort | head -1)" "zz-E-x"

# ---------- v5.9: hints.d, write-boundary hook, distiller ----------

# hints.d: matching errors pull the hint body; non-matching pull nothing; regexes valid
hint_for(){ # $1=errors text — mirrors run-cycle's hints.d loop
  local out="" hf hrx
  for hf in "$REPO"/loop/hints.d/*.hint; do
    [ -f "$hf" ] || continue
    hrx="$(sed -n 's/^MATCH:[[:space:]]*//p' "$hf" | head -1)"
    [ -n "$hrx" ] || continue
    printf '%s' "$1" | grep -qiE "$hrx" && out="$out $(basename "$hf")"
  done
  echo "$out"
}
eq "hints.d: NG8004 pulls pipe hint"     "$(hint_for 'ERROR NG8004: No pipe found' | grep -c angular-pipe)" "1"
eq "hints.d: TS2307 pulls phantom hint"  "$(hint_for 'error TS2307: Cannot find module' | grep -c phantom)" "1"
eq "hints.d: clean error pulls nothing"  "$(hint_for 'error TS2322: type mismatch' | wc -w | tr -d ' ')" "0"
RXBAD=0
for hf in "$REPO"/loop/hints.d/*.hint; do
  rx="$(sed -n 's/^MATCH:[[:space:]]*//p' "$hf" | head -1)"
  printf '' | grep -qE "$rx" 2>/dev/null; [ $? -eq 2 ] && RXBAD=$((RXBAD+1))
done
eq "hints.d: all seeded regexes valid" "$RXBAD" "0"

# write-boundary hook: JSON-block protocol (block = JSON on stdout, allow = silent)
WB="$REPO/loop/hermes-profile/agent-hooks/write-boundary.sh"
WBROOT="$(mktemp -d)"
wb(){ printf '%s' "$1" | LOOP_REPO_ROOT="$WBROOT" bash "$WB" 2>/dev/null; }
eq "hook: outside write blocked" "$(wb '{"tool_name":"write_file","tool_input":{"path":"/etc/evil.txt"}}' | grep -c '"decision":"block"')" "1"
eq "hook: inside write allowed"  "$(wb "{\"tool_name\":\"write_file\",\"tool_input\":{\"path\":\"$WBROOT/src/ok.ts\"}}" | wc -c | tr -d ' ')" "0"
eq "hook: loop/ write blocked"   "$(wb "{\"tool_name\":\"write_file\",\"tool_input\":{\"path\":\"$WBROOT/loop/x.md\"}}" | grep -c '"decision":"block"')" "1"
eq "hook: no-path call allowed"  "$(wb '{"tool_name":"terminal","tool_input":{"command":"ls"}}' | wc -c | tr -d ' ')" "0"
rm -rf "$WBROOT"

# distiller: metrics from a fixture report (codex off => pure-bash paths only)
DF="$(mktemp -d)"
( cd "$DF" && git init -q
  mkdir -p loop/reports loop/skills loop/hints.d loop/tasks loop/state
  cp "$REPO/loop/distill.sh" loop/
  RID="$(date +%Y%m%d-%H%M%S)"
  { echo "# report"; echo "- cardA: GREEN abc123, 10m, 3 files"; echo "- cardB: GREEN def456, 20m, 2 files"
    echo "- cardC: CODEX-BLOCKED, reverting"; } > "loop/reports/report-$RID.md"
  git add -A >/dev/null 2>&1; git -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1
  LOOP_DISTILL_MODEL=off bash loop/distill.sh "loop/reports/report-$RID.md" >/dev/null 2>&1
  true )
MROW="$(tail -1 "$DF/loop/reports/metrics.tsv" 2>/dev/null)"
eq "distill: metrics greens=2"   "$(printf '%s' "$MROW" | awk -F'\t' '{print $3}')" "2"
eq "distill: metrics median=15"  "$(printf '%s' "$MROW" | awk -F'\t' '{print $5}')" "15"
rm -rf "$DF"

# v5.9.2 checker integrity guard: if the checker mutates the tree, the maker state is
# restored exactly (mirror of run_checker's snapshot/restore block)
IG="$(mktemp -d)"
( cd "$IG" && git init -q
  echo "base" > a.txt && git add -A && git -c user.email=t@t -c user.name=t commit -qm init
  # maker's uncommitted work: edit tracked + add new file
  echo "maker-edit" >> a.txt && echo "new" > b.txt
  th(){ { git status --porcelain; git diff HEAD; git ls-files --others --exclude-standard | while IFS= read -r f; do printf '>>%s\n' "$f"; cat "$f"; done; } | shasum -a 256 | cut -d' ' -f1; }
  PRE="$(th)"; git add -A >/dev/null; git diff --cached HEAD > /tmp/ig-pre-$$.patch; git reset -q
  # "checker" mutates: deletes maker file, edits source
  rm b.txt && echo "checker-vandalism" >> a.txt
  if [ "$(th)" != "$PRE" ]; then
    git reset --hard HEAD >/dev/null; git clean -fd >/dev/null
    git apply --whitespace=nowarn /tmp/ig-pre-$$.patch 2>/dev/null || git apply --3way /tmp/ig-pre-$$.patch 2>/dev/null
  fi
  rm -f /tmp/ig-pre-$$.patch
  true )
eq "integrity: maker edit restored"    "$(grep -c maker-edit "$IG/a.txt")"          "1"
eq "integrity: vandalism gone"         "$(grep -c checker-vandalism "$IG/a.txt")"   "0"
eq "integrity: maker new file back"    "$([ -f "$IG/b.txt" ] && cat "$IG/b.txt")"   "new"
rm -rf "$IG"

# retire rule: 2 distinct dates + cumulative<3 => retire fires
RT="$(mktemp -d)"
printf '2026-07-04\t02-project-ui-tokens\t1\n2026-07-05\t02-project-ui-tokens\t2\n2026-07-04\t20-angular-21\t9\n2026-07-05\t20-angular-21\t14\n' > "$RT/hist.tsv"
RETIRED="$(python3 - "$RT/hist.tsv" <<'PY'
import sys, collections
dates = collections.defaultdict(set); last = {}
for ln in open(sys.argv[1]):
    p = ln.rstrip("\n").split("\t")
    if len(p) >= 3 and p[2].isdigit():
        dates[p[1]].add(p[0]); last[p[1]] = int(p[2])
for sk, ds in dates.items():
    if len(ds) >= 2 and last.get(sk, 99) < 3:
        print(sk)
PY
)"
eq "retire: low-score skill flagged"   "$RETIRED" "02-project-ui-tokens"
rm -rf "$RT"


# v5.9.4: git-shim allows plain apply (working-tree only), blocks index variants
GT2="$(mktemp -d)"; ( cd "$GT2" && git init -q && echo a > f.txt && git add -A && git -c user.email=t@t -c user.name=t commit -qm i
  printf 'diff --git a/f.txt b/f.txt\n--- a/f.txt\n+++ b/f.txt\n@@ -1 +1 @@\n-a\n+b\n' > /tmp/wip-$$.patch )
gs2(){ ( cd "$GT2" && "$REPO/loop/shims/git" "$@" ) >/dev/null 2>&1 && echo allow || echo block; }
eq "git-shim: apply allowed"          "$(gs2 apply /tmp/wip-$$.patch)"          "allow"
eq "git-shim: apply result landed"    "$(cat "$GT2/f.txt")"                     "b"
eq "git-shim: apply --index blocked"  "$(gs2 apply --index /tmp/wip-$$.patch)"  "block"
rm -rf "$GT2" /tmp/wip-$$.patch

# v5.9.4: bank_wip findings extraction mirror (last CHECKER block from a cycle log)
FL="$(mktemp)"
printf 'noise\n########## CHECKER (codex, round 1) ##########\nold findings\n########## SEMANTIC RE-ROLL 1 ##########\nstuff\n########## CHECKER (codex, round 2) ##########\nVERDICT: FAIL\n- the real reason\n' > "$FL"
WHY="$(awk '/^########## CHECKER \(codex/{b=""; f=1} f{b=b $0 ORS} END{printf "%s", b}' "$FL")"
eq "bank_wip: extracts LAST checker block" "$(printf '%s' "$WHY" | grep -c 'the real reason')" "1"
eq "bank_wip: old round excluded"          "$(printf '%s' "$WHY" | grep -c 'old findings')"    "0"
rm -f "$FL"


# v5.9.5: live DEADLINE file parse mirror
dlparse(){ local s="$1" now=1000000000 nd=""
  if [[ "$s" =~ ^\+([0-9]+)h$ ]]; then nd=$(( now + ${BASH_REMATCH[1]} * 3600 ))
  elif [[ "$s" =~ ^[0-9]{1,2}:[0-9]{2}$ ]]; then nd="abs"
  fi
  echo "${nd:-ignored}"; }
eq "live-deadline: +2h parsed"      "$(dlparse +2h)"      "1000007200"
eq "live-deadline: HH:MM parsed"    "$(dlparse 17:30)"    "abs"
eq "live-deadline: garbage ignored" "$(dlparse tomorrow)" "ignored"


# v5.9.6: BUDGET parse + driver cycle-timeout raise mirrors
bsec(){ case "$1" in *h) echo $(( ${1%h} * 3600 )) ;; *m) echo $(( ${1%m} * 60 )) ;; ''|*[!0-9]*) echo "" ;; *) echo "$1" ;; esac; }
eq "budget: 3h -> 10800"   "$(bsec 3h)"    "10800"
eq "budget: 90m -> 5400"   "$(bsec 90m)"   "5400"
eq "budget: raw secs pass" "$(bsec 5400)"  "5400"
eq "budget: garbage empty" "$(bsec huge)"  ""
cyto(){ local base=4500 cbs="$1"; [ -n "$cbs" ] && [ $(( cbs + 1200 )) -gt $base ] && echo $(( cbs + 1200 )) || echo $base; }
eq "cycle-timeout raised for 3h budget" "$(cyto 10800)" "12000"
eq "cycle-timeout floor kept for small" "$(cyto 600)"   "4500"


# v5.9.7: PROBE-GAP mirror (all probes pass + checker FAIL => gap flagged)
PGD="$(mktemp -d)"; ( cd "$PGD" && printf 'USE CASE x\nPROBE: true\nPROBE: true\n' > c.md
  PG=1
  while IFS= read -r probe; do probe="${probe#PROBE: }"; [ -z "$probe" ] && continue
    ( eval "$probe" ) >/dev/null 2>&1 || { PG=0; break; }
  done < <(grep '^PROBE: ' c.md)
  echo "$PG" > verdictgap )
eq "probe-gap: all-pass flags gap"  "$(cat "$PGD/verdictgap")" "1"
( cd "$PGD" && printf 'USE CASE x\nPROBE: true\nPROBE: false\n' > c.md
  PG=1
  while IFS= read -r probe; do probe="${probe#PROBE: }"; [ -z "$probe" ] && continue
    ( eval "$probe" ) >/dev/null 2>&1 || { PG=0; break; }
  done < <(grep '^PROBE: ' c.md)
  echo "$PG" > verdictgap )
eq "probe-gap: failing probe = no gap" "$(cat "$PGD/verdictgap")" "0"
rm -rf "$PGD"

# v5.9.7: RETIRES merge rewire mirror
MR="$(mktemp -d)"; ( cd "$MR" && mkdir -p loop/tasks
  printf 'merged card\nRETIRES: 05b-old\n' > loop/tasks/05-new.md
  printf 'x\n' > loop/tasks/05b-old.md
  printf 'y\nDEPENDS: 05b-old\n' > loop/tasks/13-dep.md
  RET="$(grep -m1 '^RETIRES:' loop/tasks/05-new.md | awk '{print $2}')"
  sed -i '' '/^RETIRES:/d' loop/tasks/05-new.md
  rm -f "loop/tasks/$RET.md"
  sed -i '' "s/^DEPENDS: $RET/DEPENDS: 05-new/" loop/tasks/*.md )
eq "merge: retired card removed"   "$([ -f "$MR/loop/tasks/05b-old.md" ] && echo yes || echo no)" "no"
eq "merge: DEPENDS rewired"        "$(grep -c 'DEPENDS: 05-new' "$MR/loop/tasks/13-dep.md")"      "1"
eq "merge: RETIRES line stripped"  "$(grep -c RETIRES "$MR/loop/tasks/05-new.md")"                "0"
rm -rf "$MR"


# v5.9.8: doubled-path RESTORE (moved real code comes back; duplicates die)
DP="$(mktemp -d)"; ( cd "$DP" && git init -q
  mkdir -p m/src && echo real > m/src/App.java && git add -A && git -c user.email=t@t -c user.name=t commit -qm i
  mkdir -p m/m/src && mv m/src/App.java m/m/src/App.java
  mkdir -p m/m/new && echo brand > m/m/new/New.java
  echo dupe > m/m/src/Dupe.java && echo orig > m/src/Dupe.java 2>/dev/null || { mkdir -p m/src; echo orig > m/src/Dupe.java; }
  git ls-files --others --exclude-standard | grep -E '^m/m/' | while IFS= read -r j; do
    correct="${j/#m\/m\//m/}"
    if [ ! -f "$correct" ]; then mkdir -p "$(dirname "$correct")"; mv "$j" "$correct"; else rm -f "$j"; fi
  done )
eq "doubled: moved real file restored" "$(cat "$DP/m/src/App.java" 2>/dev/null)"  "real"
eq "doubled: net-new file restored"    "$(cat "$DP/m/new/New.java" 2>/dev/null)"  "brand"
eq "doubled: duplicate removed"        "$([ -f "$DP/m/m/src/Dupe.java" ] && echo yes || echo no)" "no"
eq "doubled: original dupe kept"       "$(cat "$DP/m/src/Dupe.java" 2>/dev/null)" "orig"
rm -rf "$DP"


# v6.0: cluster derivation + lot boundary + fix-generation mirrors
CL="$(mktemp -d)"; mkdir -p "$CL/loop/tasks"
printf 'root card\n' > "$CL/loop/tasks/05-item-api.md"
printf 'x\nDEPENDS: 05-item-api\n' > "$CL/loop/tasks/13-form.md"
printf 'x\nDEPENDS: 13-form\n' > "$CL/loop/tasks/20-tests.md"
printf 'lone card\n' > "$CL/loop/tasks/16-pv.md"
clof(){ local n="$1" dep i=0
  while [ "$i" -lt 5 ]; do
    dep="$(grep -m1 '^DEPENDS:' "$CL/loop/tasks/$n.md" 2>/dev/null | awk '{print $2}')"
    if [ -z "$dep" ] || [ ! -f "$CL/loop/tasks/$dep.md" ]; then break; fi
    n="$dep"; i=$(( i + 1 ))
  done
  echo "$n"; }
eq "lot: chain resolves to root"     "$(clof 20-tests)"        "05-item-api"
eq "lot: direct dep resolves"        "$(clof 13-form)"         "05-item-api"
eq "lot: rootless card = own lot"    "$(clof 16-pv)"           "16-pv"
eq "lot: fix card = own lot"         "$(clof 00-F1-05-fixes)"  "00-F1-05-fixes"
rm -rf "$CL"
# fix-generation ladder
fgen(){ case "$1" in *00-F2-*) echo 3 ;; *00-F1-*) echo 2 ;; *) echo 1 ;; esac; }
eq "lot: fresh lot -> gen1"     "$(fgen '05 13 20')"          "1"
eq "lot: F1 in lot -> gen2"     "$(fgen '00-F1-05-fixes 16')" "2"
eq "lot: F2 in lot -> gen3=cap" "$(fgen '00-F2-05-fixes')"    "3"


# v6.1: council mirrors (decision parse, F3 ladder, directive extraction)
CO="$(mktemp)"
printf 'prose noise\n===DECISION===\nQUESTION: q\nCHOSEN: option A\nCLASS: PREFERENCE\nRATIONALE: r\nALTERNATIVES: B\nREVERSE-BY: revert X\n===END===\n===DIRECTIVE===\nUSE CASE: fix it\nSCOPE: full\n===END===\n' > "$CO"
DEC="$(awk '/^===DECISION===$/{f=1;next} /^===END===$/{f=0} f' "$CO")"
DIR="$(awk '/^===DIRECTIVE===$/{f=1;next} /^===END===$/{f=0} f' "$CO")"
eq "council: CLASS parsed"        "$(printf '%s\n' "$DEC" | grep -m1 '^CLASS:' | awk '{print $2}')" "PREFERENCE"
eq "council: CHOSEN parsed"       "$(printf '%s\n' "$DEC" | grep -c '^CHOSEN: option A')"           "1"
eq "council: directive extracted" "$(printf '%s\n' "$DIR" | grep -c 'USE CASE: fix it')"            "1"
rm -f "$CO"
fgen2(){ case "$1" in *00-F3-*) echo 4 ;; *00-F2-*) echo 3 ;; *00-F1-*) echo 2 ;; *) echo 1 ;; esac; }
eq "council: F2 lot -> gen3 (council convenes)" "$(fgen2 '00-F2-05-fixes')"   "3"
eq "council: F3 lot -> gen4 (final, no re-council)" "$(fgen2 '00-F3-05-council')" "4"


# v6.2: async lot-review lock mirrors
LK="$(mktemp -d)/lock"
mkdir "$LK" && eq "lot-lock: second acquire blocks" "$(mkdir "$LK" 2>/dev/null && echo got || echo blocked)" "blocked"
rmdir "$LK" && mkdir "$LK" 2>/dev/null && eq "lot-lock: freed lock reacquired" "yes" "yes"
rm -rf "$(dirname "$LK")"
# snapshot-then-clear: closer empties globals BEFORE review runs (next lot opens clean)
LSF="$(mktemp)"; printf 'a\tsha1\nb\tsha2\n' > "$LSF"
SNAP="$(awk '{print $1}' "$LSF" | tr '\n' ' ')"; : > "$LSF"
eq "lot-close: snapshot captured"  "$(echo $SNAP)" "a b"
eq "lot-close: state cleared"      "$([ -s "$LSF" ] && echo open || echo clear)" "clear"
rm -f "$LSF"


# v6.2.1: base_name strip-loop + infra-guard mirrors
bn(){ local n="$1" p; while :; do p="$n"; n="${n#zz-E-}"; n="${n#zz-D-}"; n="${n#zz-H-}"; [ "$n" = "$p" ] && break; done; echo "$n"; }
eq "base: single prefix"      "$(bn zz-E-05-api)"                 "05-api"
eq "base: stacked chaos"      "$(bn zz-D-zz-E-zz-D-21-checks)"    "21-checks"
eq "base: clean passes"       "$(bn 13-form)"                     "13-form"
eq "base: 00-F kept (lot fix)" "$(bn 00-F1-05-fixes)"             "00-F1-05-fixes"
ig(){ local dur="$1" c="$2"; if [ "$dur" -lt 2 ]; then c=$((c+1)); [ "$c" -ge 3 ] && echo "STOP" || echo "hold:$c"; else echo "route"; fi; }
eq "infra: first instant fail holds"  "$(ig 0 0)" "hold:1"
eq "infra: third instant fail stops"  "$(ig 1 2)" "STOP"
eq "infra: slow no-change routes"     "$(ig 5 2)" "route"


# v6.2.7: bank toxicity mirror
tox(){ [ "$1" -gt 5 ] && echo QUARANTINE || echo stage; }
eq "toxic: 40 deletions quarantined" "$(tox 40)" "QUARANTINE"
eq "toxic: 2 deletions stage fine"   "$(tox 2)"  "stage"


# v6.2.10: rewrite resets markers
MR2="$(mktemp)"; printf 'USE CASE new\nSCOPE: back\nESCALATED: ornith-cc\n## LESSONS old junk\nstale\n' > "$MR2"
python3 - "$MR2" <<'PYIN'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r'\n?ESCALATED:.*', '', s)
s = re.split(r'\n## LESSONS', s)[0]
open(p, 'w').write(s)
PYIN
eq "rewrite-reset: ESCALATED gone" "$(grep -c ESCALATED "$MR2")" "0"
eq "rewrite-reset: LESSONS gone"   "$(grep -c LESSONS "$MR2")"   "0"
eq "rewrite-reset: content kept"   "$(grep -c 'USE CASE new' "$MR2")" "1"
rm -f "$MR2"


# v6.4: cartographe, parse des NEW-CARD + garde un-refill
CT="$(mktemp -d)"; mkdir -p "$CT/q"
printf 'bla\n===NEW-CARD item-search===\n# Carte, recherche\nUSE CASE:\nx\n===END===\n===NEW-CARD export-pdf===\n# Carte, export\n===END===\n' | awk -v d="$CT/q" '/^===NEW-CARD /{p=$0; sub(/^===NEW-CARD /,"",p); sub(/===$/,"",p); gsub(/[^a-zA-Z0-9-]/,"",p); f=d "/50-" p ".md"; inb=1; next} /^===END===$/{if(inb){close(f)}; inb=0; next} inb{print >> f}'
eq "carto: carte 1 ecrite"  "$([ -f "$CT/q/50-item-search.md" ] && echo yes)" "yes"
eq "carto: carte 2 ecrite"  "$([ -f "$CT/q/50-export-pdf.md" ] && echo yes)"     "yes"
eq "carto: contenu ok"      "$(grep -c 'USE CASE' "$CT/q/50-item-search.md")" "1"
rm -rf "$CT"
co(){ local done="$1"; [ "$done" = 1 ] && echo skip || echo run; }
eq "carto: un seul refill par run" "$(co 1)" "skip"

echo
[ "$FAIL" -eq 0 ]

# v6.5: couverture, parse du bloc COVERAGE -> docs/coverage.md
CV="$(mktemp -d)"
printf 'bla\n===COVERAGE===\n| Creation item | COUVERT-VERT | feat: 05 |\n| Position 360 | PARTIEL | fake seul |\n===END===\n' | awk '/^===COVERAGE===$/{f=1;next} /^===END===$/{f=0} f' > "$CV/cov.md"
eq "cov: lignes extraites"  "$(grep -c '^|' "$CV/cov.md")" "2"
eq "cov: verts comptes"     "$(grep -c 'COUVERT-VERT' "$CV/cov.md")" "1"
rm -rf "$CV"

# v6.5: lentille carto, append avec dedup (le distilleur enrichit les DONNEES)
LZ="$(mktemp)"; printf -- '- CABLAGE: existante\n' > "$LZ"
printf 'x\n===CARTO-LENS===\n- CABLAGE: existante\n- AUTH: chaque ecran protege a un garde de route\n===END===\n' | awk '/^===CARTO-LENS===$/{f=1;next} /^===END===$/{f=0} f' | grep '^- ' | head -2 | while IFS= read -r L; do
  grep -qF -- "$L" "$LZ" || printf '%s\n' "$L" >> "$LZ"
done
eq "lens: dedup tenu"       "$(grep -c 'CABLAGE' "$LZ")" "1"
eq "lens: nouvelle ajoutee" "$(grep -c 'AUTH' "$LZ")"    "1"
rm -f "$LZ"


# v6.5.1: oeil FAKES, find fake/stub/mock + dedup
FK="$(mktemp -d)"; mkdir -p "$FK/src/main/java/svc"
printf 'class FakeCrmClient {}\n' > "$FK/src/main/java/svc/FakeCrmClient.java"
printf 'class RealSvc { /* fake data inside */ }\n' > "$FK/src/main/java/svc/RealSvc.java"
FKOUT="$( { find "$FK/src/main/java" \( -iname '*fake*' -o -iname '*stub*' -o -iname '*mock*' \) 2>/dev/null; grep -rli 'fake' "$FK/src/main/java" --include='*.java' 2>/dev/null; } | sort -u | wc -l | tr -d ' ')"
eq "fakes: nom + contenu dedup" "$FKOUT" "2"
rm -rf "$FK"

# v6.5.1: HANDSEED exclut les cartes du cartographe (50-)
HS="$(printf 'loop/tasks/50-carto-card.md\nloop/tasks/30-analyse-crm.md\n' | grep -v '^loop/tasks/50-' | grep -v '^$' | tr '\n' ' ')"
eq "handseed: 50- exclu, main gardee" "$HS" "loop/tasks/30-analyse-crm.md "


# v6.6: feedback_pending, l'en-tete seul ne compte pas comme contenu
FP="$(mktemp)"
printf '<!-- Boite aux lettres du loop. Ecris librement, une idee par ligne ou paragraphe.\nLe loop consomme au lancement et entre deux cycles, archive tout dans loop/feedback/\navec ce qu il a fait de chaque item, puis remet ce fichier a neuf.\nURGENT en debut de ligne met la carte en tete de file.\nLa loi (loop/*.sh) ne se change pas ici, elle reste signee par git. -->\n' > "$FP"
_pend(){ grep -vE '^[[:space:]]*(<!--|-->|$)' "$FP" 2>/dev/null | grep -vE '^(Le loop|URGENT en|La loi|avec ce qu)' | grep -q .; }
eq "feedback: entete seul = vide" "$(_pend && echo oui || echo non)" "non"
printf 'je veux plus de jaune dans les ecrans\n' >> "$FP"
eq "feedback: contenu detecte"    "$(_pend && echo oui || echo non)" "oui"
rm -f "$FP"

# v6.6: parse triage, carte 40- valide ecrite, nom hostile rejete
FT="$(mktemp -d)"; mkdir -p "$FT/t"
printf 'x\n===CARD 40-couleur-jaune===\n# Carte, jaune\nUSE CASE:\nplus de jaune\n===END===\n===CARD ../evil===\npwned\n===END===\n===CARD 99-hors-prefixe===\nnon\n===END===\n' | awk -v d="$FT/t" '/^===CARD /{p=$0; sub(/^===CARD /,"",p); sub(/===$/,"",p); gsub(/[^a-zA-Z0-9-]/,"",p); if (p !~ /^(01-)?40-/) {inb=0; next}; f=d "/" p ".md"; inb=1; next} /^===END===$/{if(inb){close(f)}; inb=0; next} inb{print >> f}'
eq "triage: carte 40- ecrite"     "$([ -f "$FT/t/40-couleur-jaune.md" ] && echo oui)" "oui"
eq "triage: noms hostiles rejetes" "$(ls "$FT/t" | wc -l | tr -d ' ')" "1"
rm -rf "$FT"

# v6.6: URGENT (01-40-) passe devant 40- mais derriere 00-F (ordre de tri de la file)
FQ="$(mktemp -d)"; touch "$FQ/40-normal.md" "$FQ/01-40-urgent.md" "$FQ/00-F1-fix.md"
eq "urgent: ordre de file" "$(ls "$FQ" | sort | tr '\n' ' ')" "00-F1-fix.md 01-40-urgent.md 40-normal.md "
rm -rf "$FQ"

# v6.6: FINI candidat, l'arithmetique ignore les 2 lignes d'entete du tableau
FC="$(mktemp)"
printf '| Use case du cahier | Etat | Preuve |\n|---|---|---|\n| Creation | COUVERT-VERT | 05 |\n| Decision | COUVERT-VERT | 06 |\n' > "$FC"
_covt="$(( $(grep -c '^|' "$FC") - 2 ))"; _covv="$(grep -c 'COUVERT-VERT' "$FC")"
eq "fini: tout vert declenche"    "$([ "$_covt" -gt 0 ] && [ "$_covv" -ge "$_covt" ] && echo oui)" "oui"
printf '| Position | PARTIEL | fake |\n' >> "$FC"
_covt="$(( $(grep -c '^|' "$FC") - 2 ))"; _covv="$(grep -c 'COUVERT-VERT' "$FC")"
eq "fini: partiel bloque"         "$([ "$_covv" -ge "$_covt" ] && echo oui || echo non)" "non"
rm -f "$FC"

# v6.6: KPI loi, les commits [loop] ne comptent pas comme intervention humaine
LK="$(printf 'v6.6: organe feedback\nloop: feedback consomme [loop]\nfix: dedup lentilles\ndistill: run x [loop]\n' | grep -vc '\[loop\]')"
eq "kpi loi: humains seuls comptes" "$LK" "2"


# v6.7: e2e.sh, chemin SKIP si infra absente (jamais bloquant)
E7="$(mktemp -d)"; mkdir -p "$E7/loop" "$E7/frontend"
cp loop/e2e.sh "$E7/loop/"
( cd "$E7" && PATH="/usr/bin:/bin" bash loop/e2e.sh >/dev/null 2>&1 ); _rc=$?
eq "e2e: skip sans playwright" "$_rc" "3"
rm -rf "$E7"

# v6.7: carte de reparation, extraction de preuve bornee (jamais de log geant dans une carte)
EL="$(mktemp)"; for i in $(seq 1 200); do echo "ligne $i erreur ecran /items vide"; done > "$EL"
eq "e2e: preuve bornee a 40 lignes" "$(grep -vE '^\s*$' "$EL" | tail -40 | wc -l | tr -d ' ')" "40"
rm -f "$EL"

# v6.7: ordre de file complet, la reparation runtime derriere les fix-lots, devant le reste
EO="$(mktemp -d)"; touch "$EO/00-F1-x.md" "$EO/01-40-urgent.md" "$EO/01-45-e2e-repare.md" "$EO/12-cablage.md"
eq "e2e: place dans la file" "$(ls "$EO" | sort | head -3 | tr '\n' ' ')" "00-F1-x.md 01-40-urgent.md 01-45-e2e-repare.md "
rm -rf "$EO"


# v6.8: hook pre_verify, PROBE en echec => continue avec message
PV="$(mktemp -d)"
printf 'USE CASE x\nPROBE: /usr/bin/false\nSCOPE: back\n' > "$PV/card.md"
OUT="$(printf '{"coding": true, "attempt": 0}' | LOOP_CARD="$PV/card.md" LOOP_REPO_ROOT="$PV" LOOP_PREVERIFY=1 bash loop/hermes-profile/agent-hooks/probe-verify.sh)"
eq "preverify: echec => continue"   "$(printf '%s' "$OUT" | grep -c '"action": "continue"')" "1"
# PROBE qui passe => silence (le tour se termine)
printf 'USE CASE x\nPROBE: /usr/bin/true\n' > "$PV/card.md"
OUT="$(printf '{"coding": true, "attempt": 0}' | LOOP_CARD="$PV/card.md" LOOP_REPO_ROOT="$PV" bash loop/hermes-profile/agent-hooks/probe-verify.sh)"
eq "preverify: vert => silence"     "${OUT:-vide}" "vide"
# auto-throttle: attempt 2 => silence meme sur echec
printf 'USE CASE x\nPROBE: /usr/bin/false\n' > "$PV/card.md"
OUT="$(printf '{"coding": true, "attempt": 2}' | LOOP_CARD="$PV/card.md" LOOP_REPO_ROOT="$PV" bash loop/hermes-profile/agent-hooks/probe-verify.sh)"
eq "preverify: throttle attempt 2"  "${OUT:-vide}" "vide"
# format liste: backticks purs executes, ligne avec prose sautee (semantique humaine)
printf 'USE CASE x\nPROBE\n- `/usr/bin/false`\n- `rg -n pattern f.java` must not show default\n' > "$PV/card.md"
OUT="$(printf '{"coding": true, "attempt": 0}' | LOOP_CARD="$PV/card.md" LOOP_REPO_ROOT="$PV" bash loop/hermes-profile/agent-hooks/probe-verify.sh)"
eq "preverify: liste backticks pure" "$(printf '%s' "$OUT" | grep -c 'continue')" "1"
eq "preverify: prose sautee"         "$(printf '%s' "$OUT" | grep -c 'must not show')" "0"
# pas de carte => silence instantane (usage interactif hermes non affecte)
OUT="$(printf '{}' | LOOP_REPO_ROOT="$PV" bash loop/hermes-profile/agent-hooks/probe-verify.sh)"
eq "preverify: sans carte => no-op"  "${OUT:-vide}" "vide"
rm -rf "$PV"


# v6.8.2: toute fonction du driver est definie AVANT son premier appel top-level
# (base_name appele ligne ~295, defini ligne ~372: detonation au premier run avec carte F au demarrage)
FD="$(grep -n '^base_name()' loop/loop-overnight.sh | head -1 | cut -d: -f1)"
FC="$(grep -n 'base_name ' loop/loop-overnight.sh | grep -v '^.*base_name()' | head -1 | cut -d: -f1)"
eq "ordre: base_name defini avant appel" "$([ "${FD:-99999}" -lt "${FC:-0}" ] && echo oui)" "oui"


# v6.9 C1: le contrat stack surcharge, et son absence = defauts historiques exacts
SK="$(mktemp -d)"
( BACK_DIR="backend"; FRONT_DIR="frontend"; BACK_PORT="8081"
  [ -f "$SK/stack.sh" ] && . "$SK/stack.sh"
  printf '%s|%s|%s\n' "$BACK_DIR" "$FRONT_DIR" "$BACK_PORT" ) > "$SK/out1"
eq "stack: absent = defauts"  "$(cat "$SK/out1")" "backend|frontend|8081"
printf 'BACK_DIR="app_flutter"\nBACK_PORT="54321"\n' > "$SK/stack.sh"
( BACK_DIR="backend"; FRONT_DIR="frontend"; BACK_PORT="8081"
  [ -f "$SK/stack.sh" ] && . "$SK/stack.sh"
  printf '%s|%s|%s\n' "$BACK_DIR" "$FRONT_DIR" "$BACK_PORT" ) > "$SK/out2"
eq "stack: surcharge partielle" "$(cat "$SK/out2")" "app_flutter|frontend|54321"
rm -rf "$SK"


# v6.9 C2: sync des skills TIER-marques vers le store (miroir de la logique distill)
GS="$(mktemp -d)"; mkdir -p "$GS/store/universel" "$GS/sk"
printf 'TIER: universel\nregle A\n' > "$GS/sk/a.md"
printf 'TIER: stack\nidiome B\n' > "$GS/sk/b.md"
printf 'regle projet sans tier\n' > "$GS/sk/c.md"
for sk in "$GS/sk"/*.md; do
  case "$(grep -m1 '^TIER:' "$sk" 2>/dev/null | awk '{print $2}')" in
    universel) cp -f "$sk" "$GS/store/universel/" ;;
    stack)     mkdir -p "$GS/store/stack-x"; cp -f "$sk" "$GS/store/stack-x/" ;;
  esac
done
eq "store: universel monte"   "$(ls "$GS/store/universel" | tr -d '\n')" "a.md"
eq "store: stack monte"       "$(ls "$GS/store/stack-x" | tr -d '\n')"   "b.md"
eq "store: projet reste"      "$(find "$GS/store" -name c.md | wc -l | tr -d ' ')" "0"
rm -rf "$GS"


# v6.9 C3: loop-init seme un loop complet et syntaxiquement valide dans un repo neuf
LI="$(mktemp -d)"; git -C "$LI" init -q
bash loop/loop-init.sh "$LI" --stack angular-spring >/dev/null 2>&1
eq "init: driver seme"        "$([ -f "$LI/loop/loop-overnight.sh" ] && echo oui)" "oui"
eq "init: contrat stack pack" "$(grep -c 'STACK_NAME=\"angular-spring\"' "$LI/loop/stack.sh")" "1"
eq "init: lentilles voyagent" "$([ -s "$LI/loop/carto-lenses.md" ] && echo oui)" "oui"
eq "init: carte bootstrap"    "$(grep -c 'cartographie initiale' "$LI/loop/tasks/01-cartographie-initiale.md")" "1"
eq "init: refus d ecraser"    "$(bash loop/loop-init.sh "$LI" >/dev/null 2>&1; echo $?)" "2"
_synerr=0; for f in "$LI"/loop/*.sh; do bash -n "$f" 2>/dev/null || _synerr=$((_synerr+1)); done
eq "init: tous scripts parsent" "$_synerr" "0"
# stack inconnu => squelette a remplir
LJ="$(mktemp -d)"; git -C "$LJ" init -q
bash loop/loop-init.sh "$LJ" --stack flutter-supabase >/dev/null 2>&1
eq "init: squelette stack inconnu" "$([ "$(grep -c 'A REMPLIR' "$LJ/loop/stack.sh")" -ge 1 ] && echo oui)" "oui"
rm -rf "$LI" "$LJ"


# v6.10: LOOP_MAKER_KIND=codex, la branche frontier existe et est bien formee
eq "frontier: branche codex presente"  "$(grep -c 'EKIND" = "codex"' loop/run-cycle.sh)" "1"
eq "frontier: sandbox workspace"       "$(grep -c -- '-C "\$ROOT" "\$1"' loop/run-cycle.sh)" "1"
eq "frontier: hermes reste le defaut"  "$([ "$(grep -c 'hermes -m "\$MAKER"' loop/run-cycle.sh)" -ge 2 ] && echo oui)" "oui"


# v6.10.1: profil maker par projet, jamais partage
PP="$(mktemp -d)"; git -C "$PP" init -q
bash loop/loop-init.sh "$PP" --stack angular-spring >/dev/null 2>&1
eq "profil: projet seme a le sien" "$(grep -c 'LOOP_PROFILE_DIR="$HOME/.hermes-loop-' "$PP/loop/stack.sh")" "1"
grep -q 'LOOP_PROFILE_DIR' loop/stack.sh 2>/dev/null || eq "profil: defaut conserve si le contrat ne le definit pas" "$(grep -c 'LOOP_PROFILE_DIR' loop/stack.sh)" "0"
rm -rf "$PP"


# v6.10.2: deux loops, un store, zero ecrasement
FM="$(mktemp -d)"
printf -- '- A: lentille projet-a\n' > "$FM/local.md"; printf -- '- B: lentille projet-b\n' > "$FM/store.md"
# montee: local -> store (A rejoint B)
grep '^- ' "$FM/local.md" | while IFS= read -r L; do grep -qF -- "$L" "$FM/store.md" || printf '%s\n' "$L" >> "$FM/store.md"; done
eq "fusion: montee sans ecrasement" "$(sort "$FM/store.md" | tr -d '\n')" "- A: lentille projet-a- B: lentille projet-b"
# descente: store -> local (B rejoint A), idempotente
for i in 1 2; do grep '^- ' "$FM/store.md" | while IFS= read -r L; do grep -qF -- "$L" "$FM/local.md" || printf '%s\n' "$L" >> "$FM/local.md"; done; done
eq "fusion: descente idempotente" "$(wc -l < "$FM/local.md" | tr -d ' ')" "2"
# collision de skill: meme nom, contenu different => cote a cote
mkdir -p "$FM/u"; printf 'v-a\n' > "$FM/u/probe-design.md"; printf 'v-b\n' > "$FM/probe-design.md"
_PSLUG=monprojet
_sync_skill(){ local dst="$2/$(basename "$1")"; if [ ! -f "$dst" ]; then cp "$1" "$dst"; elif ! cmp -s "$1" "$dst"; then cp "$1" "$2/$(basename "$1" .md)-$_PSLUG.md"; fi; }
_sync_skill "$FM/probe-design.md" "$FM/u"
eq "fusion: collision cote a cote" "$(ls "$FM/u" | sort | tr '\n' ' ')" "probe-design-monprojet.md probe-design.md "
eq "fusion: original intact"       "$(cat "$FM/u/probe-design.md")" "v-a"
rm -rf "$FM"


# v6.11: maker claude (Opus) route par la loi, pas bricole
eq "frontier: branche claude presente" "$(grep -c 'EKIND" = "claude"' loop/run-cycle.sh)" "1"
eq "frontier: opus par defaut"         "$(grep -c 'claude --model "${LOOP_MAKER:-claude-opus-4-8}" --effort' loop/run-cycle.sh)" "1"


# v6.12: adoptions du loop pilote (premiere pollinisation inter-sessions)
# v6.45.1 inverse la loi v6.9: le 2e source (store global) re-clobberait GATE_BACK_CMD=''
# par-dessus le defaut (BUG C, 9 faux REDCOMPILE). UNE source, en tete, avant les defauts.
eq "pilote: run-cycle source stack"   "$(grep -c '\[ -f "$ROOT/loop/stack.sh" \] && \. "$ROOT/loop/stack.sh"' loop/run-cycle.sh)" "1"
eq "pilote: routes via FRONT_DIR"     "$(grep -c 'routes="\$ROOT/\$FRONT_DIR/src/app/app.routes.ts"' loop/run-cycle.sh)" "1"
eq "pilote: env -i maker claude"      "$(grep -c 'env -i HOME="\$HOME" USER="\$USER" TERM=xterm PATH="\$MAKER_PATH"' loop/run-cycle.sh)" "1"
eq "pilote: port refus parametre"     "$(grep -c 'tcp:"\$BACK_PORT"' loop/loop-overnight.sh)" "1"
LN="$(mktemp -d)"; git -C "$LN" init -q
bash loop/loop-init.sh "$LN" --stack angular-spring >/dev/null 2>&1
eq "pilote: init copie loop-init"     "$([ -f "$LN/loop/loop-init.sh" ] && echo oui)" "oui"
eq "pilote: init copie hints"         "$(ls "$LN/loop/hints.d/" 2>/dev/null | wc -l | tr -d ' ' | sed 's/^0$/vide/')" "$(ls loop/hints.d/ | wc -l | tr -d ' ')"
rm -rf "$LN"


# v6.13: pannes systemiques pilote adoptees
eq "v613: smoke parametre"        "$(grep -c 'SMOKE_PATH="${SMOKE_PATH:-/api/health}"' loop/verify.sh)" "1"
eq "v613: sante parametree"       "$(grep -c '\$BACK_PORT\$HEALTH_PATH' loop/verify.sh)" "1"
eq "v613: tmp verify par projet"  "$(grep -c '/tmp/\$PSLUG-verify' loop/verify.sh)" "3"
eq "v613: tmp lite par projet"    "$(grep -c '/tmp/\$PSLUG_RC-lite' loop/run-cycle.sh)" "4"
eq "v613: zero cc- statique"      "$(grep -hoE '/tmp/cc-[a-z-]+\.(log|json)' loop/verify.sh loop/run-cycle.sh loop/loop-overnight.sh loop/e2e.sh 2>/dev/null | wc -l | tr -d ' ')" "0"
eq "v613: extracteur suit le slug"  "$(grep -c '/tmp/\$PSLUG_D-verify' loop/loop-overnight.sh)" "5"
# escalade kind-aware (miroir du case)
_esc(){ case "$1" in claude) echo claude-opus-4-8;; codex) echo codex;; *) echo ornith-cc;; esac; }
eq "v613: escalade claude=opus"   "$(_esc claude)" "claude-opus-4-8"
eq "v613: escalade hermes=ornith" "$(_esc hermes)" "ornith-cc"
eq "v613: case dans le driver"    "$(grep -c '_ESC_DEFAULT="claude-opus-4-8"' loop/loop-overnight.sh)" "1"


# v6.14: le domaine du projet est un parametre, plus jamais en dur dans les prompts
eq "domaine: token en constitution"  "$(grep -c '{{PROJECT_DOMAIN}}' loop/constitution.md)" "1"
eq "domaine: substitution reelle"    "$(PROJECT_DOMAIN=tourisme; sed "s/{{PROJECT_DOMAIN}}/$PROJECT_DOMAIN/" loop/constitution.md | head -1 | grep -c 'v1 of tourisme')" "1"
eq "domaine: carto sur variable"     "$(grep -c 'CARTOGRAPHE.*\$PROJECT_DOMAIN' loop/loop-overnight.sh)" "1"
eq "domaine: zero en-dur restant"    "$(head -1 loop/constitution.md | grep -c '{{PROJECT_DOMAIN}}')" "1"
eq "domaine: placeholder dans le pack" "$(grep -c 'PROJECT_DOMAIN="A REMPLIR' loop/stack.d/angular-spring.sh)" "1"


# v6.14.1: zero identite projet dans la loi generique (elle vit dans stack.sh)
# Les motifs interdits ne sont pas un nom de projet en dur: ils sont DERIVES du contrat du
# projet courant (nom du depot, domaine, dossiers de modules, cle de session). Meme garde,
# portable sur n'importe quel depot.
_ID_NAME="$(basename "$REPO")"
_ID_DOM="$( . loop/stack.sh 2>/dev/null; printf '%s' "${PROJECT_DOMAIN:-}" )"
_ID_DIRS="$( . loop/stack.sh 2>/dev/null; printf '%s\n%s\n' "${BACK_DIR:-}" "${FRONT_DIR:-}" | grep -v '^$' | paste -sd'|' - )"
if [ "${#_ID_NAME}" -ge 4 ]; then
  eq "identite: constitution neutre" "$(grep -ci -- "$_ID_NAME" loop/constitution.md)" "0"
  eq "identite: conseil neutre"      "$(grep -ci -- "$_ID_NAME" loop/council.sh)" "0"
fi
eq "identite: zero metier dans conseil" "$(if [ -n "$_ID_DOM" ]; then grep -ciF -- "$_ID_DOM" loop/council.sh || true; else echo 0; fi)" "0"
eq "identite: zero metier en constitution" "$(if [ -n "$_ID_DOM" ]; then grep -ciF -- "$_ID_DOM" loop/constitution.md || true; else echo 0; fi)" "0"
eq "identite: zero dir projet en constitution" "$(if [ -n "$_ID_DIRS" ]; then grep -cE -- "$_ID_DIRS" loop/constitution.md || true; else echo 0; fi)" "0"
eq "identite: zero dir projet en lentilles"    "$(if [ -n "$_ID_DIRS" ]; then grep -cE -- "$_ID_DIRS" loop/carto-lenses.md || true; else echo 0; fi)" "0"
eq "identite: tokens dir presents"          "$([ "$(grep -c '{{FRONT_DIR}}\|{{BACK_DIR}}' loop/constitution.md)" -gt 0 ] && echo oui)" "oui"
# v6.27: garde TOTALE, constitution.md ne contient AUCUN nom propre projet (tous dans STACK_BRIEF/stack.sh)
eq "identite: constitution zero nom propre" "$(grep -ciE 'styles.css|Spring Boot|Angular 21' loop/constitution.md)" "0"
eq "identite: placeholder STACK_BRIEF"      "$(grep -c '{{STACK_BRIEF}}' loop/constitution.md)" "1"
eq "identite: brief dans le contrat"        "$(grep -c 'STACK_BRIEF=' loop/stack.d/angular-spring.sh)" "1"


# v6.15: sentinelle quota, detection sur signatures reelles, gating hermes
UQ="$(mktemp -d)"
printf 'normal output\nError: 429 Too Many Requests\nretrying...\n' > "$UQ/cycle.log"
eq "quota: signature detectee"  "$(grep -hiE 'rate.?limit|429|usage limit|quota exceeded|too many requests|out of.*credits' "$UQ/cycle.log" | wc -l | tr -d ' ')" "1"
printf 'clean build, all tests pass\n' > "$UQ/clean.log"
eq "quota: log propre silencieux" "$(grep -hiE 'rate.?limit|429|usage limit|quota exceeded' "$UQ/clean.log" | wc -l | tr -d ' ')" "0"
eq "quota: gate hermes present"   "$(grep -c 'LOOP_MAKER_KIND:-hermes}" = "hermes" \] && return 0' loop/loop-overnight.sh)" "1"
eq "quota: crochets contrat"      "$([ "$(grep -c 'USAGE_CLAUDE_CMD\|USAGE_CODEX_CMD' loop/loop-overnight.sh)" -ge 3 ] && echo oui)" "oui"
rm -rf "$UQ"


# v6.16: kind effectif par carte (escalade change la FAMILLE, pas seulement le modele)
maker_kind_for(){ case "$1" in claude-*|*opus*|*sonnet*|*haiku*) echo claude;; codex|gpt-*|o1-*|o3-*|o4-*) echo codex;; *) echo "${LOOP_MAKER_KIND:-hermes}";; esac; }
eq "kind: opus escalade sous codex" "$(LOOP_MAKER_KIND=codex; maker_kind_for claude-opus-4-8)" "claude"
eq "kind: codex reste codex"        "$(LOOP_MAKER_KIND=codex; maker_kind_for codex)" "codex"
eq "kind: qwen sous codex = global" "$(LOOP_MAKER_KIND=codex; maker_kind_for qwen3-coder:30b)" "codex"
eq "kind: qwen sous hermes = local" "$(LOOP_MAKER_KIND=hermes; maker_kind_for qwen3-coder:30b)" "hermes"
eq "kind: ornith escalade local"    "$(LOOP_MAKER_KIND=hermes; maker_kind_for ornith-cc)" "hermes"
eq "kind: invoke lit EKIND"         "$(grep -c 'EKIND="$(maker_kind_for "$MAKER")"' loop/run-cycle.sh)" "1"


# v6.17: capteur fidelite maquette, apparie et detecte l'ecart structurel
MF="$(mktemp -d)"; mkdir -p "$MF/design/screens" "$MF/frontend/src/app/pages/items" "$MF/loop"
cp loop/maquette-fidelity.sh "$MF/loop/"
# maquette riche (5 boutons, 4 champs), page vide
printf '<button>a</button><button>b</button><button>c</button><button>d</button><button>e</button><input><input><input><input>' > "$MF/design/screens/items-list.html"
printf '<div>vide</div>' > "$MF/frontend/src/app/pages/items/items.html"
OUT="$(cd "$MF" && bash loop/maquette-fidelity.sh "$MF" 2>/dev/null)"
eq "maqfid: ecart detecte"      "$(printf '%s' "$OUT" | grep -c 'ECART maquette.*items-list')" "1"
eq "maqfid: doc genere"         "$([ -f "$MF/docs/maquette-fidelity.md" ] && echo oui)" "oui"
# ecran sans page
printf '<button>x</button>' > "$MF/design/screens/orphelin.html"
OUT2="$(cd "$MF" && bash loop/maquette-fidelity.sh "$MF" 2>/dev/null)"
eq "maqfid: ecran non construit" "$(printf '%s' "$OUT2" | grep -c "orphelin.*pas de page")" "1"
# page conforme (memes comptes) => pas d'ecart
rm "$MF/design/screens/orphelin.html"
printf '<button>a</button><button>b</button><button>c</button><button>d</button><button>e</button><input><input><input><input>' > "$MF/frontend/src/app/pages/items/items.html"
OUT3="$(cd "$MF" && bash loop/maquette-fidelity.sh "$MF" 2>/dev/null)"
eq "maqfid: conforme silencieux" "$(printf '%s' "$OUT3" | grep -c 'ECART maquette.*items-list')" "0"
rm -rf "$MF"


# v6.18: garde anti-doublon de driver par worktree
GD="$(mktemp -d)"; mkdir -p "$GD/loop"
_guard(){ # $1=running-file-content ; renvoie REFUSE ou OK selon un pid vivant different
  local other="$1"
  if [ -n "$other" ] && [ "$other" != "$$" ] && kill -0 "$other" 2>/dev/null && [ "${LOOP_FORCE:-0}" != "1" ]; then echo REFUSE; else echo OK; fi
}
sleep 300 & LIVE=$!   # pid vivant, different de nous
eq "doublon: pid vivant refuse"  "$(_guard "$LIVE")" "REFUSE"
eq "doublon: LOOP_FORCE outrepasse" "$(LOOP_FORCE=1; _guard "$LIVE")" "OK"
kill $LIVE 2>/dev/null; wait $LIVE 2>/dev/null
eq "doublon: pid mort passe"     "$(_guard "$LIVE")" "OK"
eq "doublon: fichier vide passe" "$(_guard "")" "OK"
eq "doublon: garde dans driver"  "$(grep -c 'REFUSE: un driver tourne deja' loop/loop-overnight.sh)" "1"
rm -rf "$GD"
# crochets usage adoptes dans le pack stack
eq "usage: crochet claude dans pack" "$(grep -c 'USAGE_CLAUDE_CMD=' loop/stack.d/angular-spring.sh)" "1"
eq "usage: crochet codex dans pack"  "$(grep -c 'USAGE_CODEX_CMD=' loop/stack.d/angular-spring.sh)" "1"


# v6.19: debit maker par famille, mesure et mediane
MP="$(mktemp)"
printf 'r1\tc1\tcodex\tcodex\t180\tGREEN\nr1\tc2\tcodex\tcodex\t220\tGREEN\nr1\tc3\tclaude\topus\t560\tGREEN\nr1\tc4\tclaude\topus\t520\tGREEN\nr1\tc5\tcodex\tcodex\t9\tRED\n' > "$MP"
OUT="$(python3 - "$MP" <<'PYP'
import sys, collections, statistics
rows=[l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip()]
g=collections.defaultdict(list)
for r in rows:
    if len(r)>=6 and r[5]=="GREEN":
        g[r[2]].append(int(r[4]))
for k in sorted(g,key=lambda k:statistics.median(g[k])):
    print(k, int(statistics.median(g[k])), len(g[k]))
PYP
)"
eq "perf: codex plus rapide"   "$(printf '%s' "$OUT" | head -1 | awk '{print $1}')" "codex"
eq "perf: mediane codex 200"   "$(printf '%s' "$OUT" | awk '/codex/{print $2}')" "200"
eq "perf: RED exclu du debit"  "$(printf '%s' "$OUT" | awk '/codex/{print $3}')" "2"
eq "perf: 4 issues instrumentees" "$(grep -c '  *perf_log ' loop/loop-overnight.sh)" "4"
rm -f "$MP"


# v6.20: decharge MLX conditionnel (STOP humain ou NIGHT-PLAN absent => unload)
UD="$(mktemp -d)"; mkdir -p "$UD/loop"
_should_unload(){ [ -f "$UD/loop/STOP" ] || [ ! -f "$UD/loop/NIGHT-PLAN" ]; }
: > "$UD/loop/NIGHT-PLAN"    # relance planifiee, pas de STOP
_should_unload && echo A > "$UD/r" || echo B > "$UD/r"; eq "unload: relance planifiee garde" "$(cat "$UD/r")" "B"
: > "$UD/loop/STOP"          # STOP humain malgre NIGHT-PLAN
_should_unload && echo A > "$UD/r" || echo B > "$UD/r"; eq "unload: STOP humain decharge" "$(cat "$UD/r")" "A"
rm -f "$UD/loop/NIGHT-PLAN" "$UD/loop/STOP"   # fin normale sans plan
_should_unload && echo A > "$UD/r" || echo B > "$UD/r"; eq "unload: fin sans plan decharge" "$(cat "$UD/r")" "A"
eq "unload: cable dans cleanup" "$([ "$(grep -c 'lms unload --all' loop/loop-overnight.sh)" -ge 1 ] && echo oui)" "oui"
rm -rf "$UD"


# v6.21: digest matin, compose depuis les artefacts, autonome, envoi non force
DG="$(mktemp -d)"; mkdir -p "$DG/loop/reports" "$DG/loop/state/queue"
cp loop/morning-digest.sh "$DG/loop/"
printf '# rapport\n- green: 3   red: 0   blocked: 1\n- E2E RUNTIME: VERT\n- COUVERTURE: 5/8 use cases verts\n' > "$DG/loop/reports/report-20260707-x.md"
printf 'run\thours\tgreens\tgph\tmed\tblocked\tred\tlaw_patches\n20260707-x\t5\t3\t0.6\t22\t1\t0\t0\n' > "$DG/loop/reports/metrics.tsv"
touch "$DG/loop/state/queue/26-position.md" "$DG/loop/state/queue/30-crm.md"
OUT="$(cd "$DG" && HOME=/nonexistent bash loop/morning-digest.sh "$DG" 2>/dev/null)"
eq "digest: resume present"   "$(printf '%s' "$OUT" | grep -c 'green: 3')" "1"
eq "digest: e2e present"      "$(printf '%s' "$OUT" | grep -c 'E2E RUNTIME: VERT')" "1"
eq "digest: couverture"       "$(printf '%s' "$OUT" | grep -c '5/8 use cases')" "1"
eq "digest: file comptee"     "$(printf '%s' "$OUT" | grep -c 'file restante: 2')" "1"
eq "digest: prochaine carte"  "$(printf '%s' "$OUT" | grep -c 'prochaine: 26-position')" "1"
eq "digest: cable en fin run" "$(grep -c 'bash loop/morning-digest.sh' loop/loop-overnight.sh)" "1"
rm -rf "$DG"


# v6.22 BUG A: le tag ESCALATED cross-famille ne ressuscite pas l'autre famille
esc_family(){ case "$1" in claude-*|*opus*|*sonnet*|*haiku*) echo claude;; codex|gpt-*|o1-*|o3-*|o4-*) echo codex;; *) echo hermes;; esac; }
_resolve(){ # $1=tag carte $2=escalade du run  -> modele effectif
  if [ -n "$1" ] && [ "$(esc_family "$1")" = "$(esc_family "$2")" ]; then echo "$1"; else echo "$2"; fi
}
eq "escA: tag opus sous run codex -> codex" "$(_resolve claude-opus-4-8 codex)" "codex"
eq "escA: tag opus sous run claude -> opus" "$(_resolve claude-opus-4-8 claude-opus-4-8)" "claude-opus-4-8"
eq "escA: tag ornith sous run codex -> codex" "$(_resolve ornith-cc codex)" "codex"
eq "escA: tag ornith sous run hermes -> ornith" "$(_resolve ornith-cc ornith-cc)" "ornith-cc"
eq "escA: garde dans le driver" "$(grep -c 'esc_family "$CARD_ESC"' loop/loop-overnight.sh)" "1"


# v6.23: PARK apres split-me repete + decoupage cartographe
PK="$(mktemp -d)"; mkdir -p "$PK/loop/tasks" "$PK/loop/state/parked" "$PK/loop/state/queue"
printf 'USE CASE gros\n## LESSONS vieux\nx\nSPLIT-ME: failed both makers\n' > "$PK/loop/tasks/depot-api.md"
# simuler la decision de park: carte avec SPLIT-ME + LESSONS re-echoue
_should_park(){ grep -q '^SPLIT-ME:' "$1" && grep -q '^## LESSONS' "$1"; }
_should_park "$PK/loop/tasks/depot-api.md" && echo A > "$PK/r" || echo B > "$PK/r"
eq "park: split-me+lessons => park" "$(cat "$PK/r")" "A"
printf 'USE CASE frais\n' > "$PK/loop/tasks/neuf.md"
_should_park "$PK/loop/tasks/neuf.md" && echo A > "$PK/r" || echo B > "$PK/r"
eq "park: carte fraiche pas parkee" "$(cat "$PK/r")" "B"
# parsing du decoupage codex (2 sous-cartes)
printf 'bla\n===NEW-CARD depot-partie-1===\nUSE CASE 1\n===END===\n===NEW-CARD depot-partie-2===\nUSE CASE 2\n===END===\n' | awk '/^===NEW-CARD /{p=$0; sub(/^===NEW-CARD /,"",p); sub(/===$/,"",p); gsub(/[^a-zA-Z0-9-]/,"",p); f="'"$PK"'/loop/state/queue/50-" p ".md"; inb=1; n++; if(n>3){inb=0}; next} /^===END===$/{if(inb){close(f)}; inb=0; next} inb{print >> f}'
eq "split: 2 sous-cartes ecrites" "$(ls "$PK/loop/state/queue/"50-depot-partie-*.md 2>/dev/null | wc -l | tr -d ' ')" "2"
eq "park: garde dans driver"      "$(grep -c 'PARKED (echec repete apres split-me)' loop/loop-overnight.sh)" "1"
eq "split: passe carto dans driver" "$(grep -c 'decoupage auto de la carte parkee' loop/loop-overnight.sh)" "1"
rm -rf "$PK"


# v6.24: socle front, comptage des pages reelles
FR="$(mktemp -d)"; mkdir -p "$FR/pages/a" "$FR/pages/b" "$FR/pages/c"
printf '@Component({templateUrl:"./a.html"})\nexport class A{}' > "$FR/pages/a/a.ts"
printf '@Component({template:`<div>x</div>`})\nexport class B{}' > "$FR/pages/b/b.ts"
printf '@Component({})\nexport class C{}' > "$FR/pages/c/c.ts"   # shell sans template
eq "socle: 2 pages reelles sur 3" "$(grep -rlE 'templateUrl|template *:' "$FR/pages" --include='*.ts' | wc -l | tr -d ' ')" "2"
eq "socle: lentille presente"     "$(grep -c 'FONDATION-FRONT' loop/carto-lenses.md)" "1"
eq "socle: signal dans carto"     "$([ "$(grep -c 'SOCLE FRONT' loop/loop-overnight.sh)" -ge 1 ] && echo oui)" "oui"
rm -rf "$FR"


# v6.25: relecteur de lot diversifiable (casse codex-juge-codex)
eq "lotchair: option claude presente" "$(grep -c 'LOOP_LOT_CHAIR:-codex}" = "claude"' loop/loop-overnight.sh)" "1"
eq "lotchair: fallback codex garde"   "$(grep -c 'OUT=.*codex exec --sandbox read-only --skip-git-repo-check "\$RVP"' loop/loop-overnight.sh)" "1"
_chair(){ if [ "${LOOP_LOT_CHAIR:-codex}" = "claude" ]; then echo claude; else echo codex; fi; }
eq "lotchair: defaut codex"    "$(_chair)" "codex"
eq "lotchair: claude si demande" "$(LOOP_LOT_CHAIR=claude; _chair)" "claude"


# v6.26: decodage speculatif opt-in (defaut OFF, flags corrects quand ON)
_spec(){ if [ "${LOOP_SPECULATIVE:-0}" = "1" ]; then echo "--speculative-draft-simple --speculative-draft-model ${LOOP_DRAFT_MODEL:-qwen/qwen3-1.7b} --speculative-draft-max-tokens ${LOOP_DRAFT_MAX:-6}"; else echo ""; fi; }
eq "spec: off par defaut"        "$(_spec)" ""
eq "spec: on ajoute le draft"    "$(LOOP_SPECULATIVE=1; _spec | grep -c 'qwen/qwen3-1.7b')" "1"
eq "spec: draft surchargeable"   "$(LOOP_SPECULATIVE=1 LOOP_DRAFT_MODEL=qwen/qwen3-0.6b; _spec | grep -c 'qwen3-0.6b')" "1"
eq "spec: cable dans le driver"  "$(grep -c 'LOOP_SPECULATIVE:-0} = 1\|LOOP_SPECULATIVE:-0}" = "1"' loop/loop-overnight.sh)" "1"


# v6.27.1: sentinelle quota, faux positif crash dump exclu, vrai rate-limit detecte
QF="$(mktemp)"
printf '  "codeSigningTrustLevel" : 4294967295,\n  "threadState" : { "x" : 1 },\n' > "$QF"
_qhit(){ grep -hiE 'rate.?limit.?exceeded|rate.?limited|\b429\b (too many|status)|too many requests|quota (exceeded|exhausted)|usage limit reached|out of (credits|quota)|retry.?after|insufficient_quota|error.?429' "$1" 2>/dev/null | grep -viE 'codeSigningTrustLevel|threadState|__pthread_kill|imageIndex|POINTER_BEING_FREED|crashed|backtrace|libmalloc'; }
eq "quota: crash dump 4294967295 ignore" "$(_qhit "$QF" | wc -l | tr -d ' ')" "0"
printf 'Error: 429 Too Many Requests\nretry-after: 30\n' > "$QF"
eq "quota: vrai 429 detecte"             "$([ "$(_qhit "$QF" | wc -l | tr -d ' ')" -ge 1 ] && echo oui)" "oui"
printf 'HTTP 200 OK, all good, build passed\n' > "$QF"
eq "quota: log propre silencieux"        "$(_qhit "$QF" | wc -l | tr -d ' ')" "0"
rm -f "$QF"


# v6.28 (finding 17): compteur fix-lot PERSISTANT par feature-base, cap dur -> conseil
LG="$(mktemp -d)"; mkdir -p "$LG/lot-gen"
_gen(){ local base="$1"; local cf="$LG/lot-gen/$base.count"; local g=$(( $(cat "$cf" 2>/dev/null || echo 0) + 1 )); echo "$g" > "$cf"; echo "$g"; }
_route(){ local g="$1"; local max="${LOOP_LOT_MAXGEN:-2}"; if [ "$g" -le "$max" ]; then echo "fix"; elif [ "$g" -eq $((max+1)) ]; then echo "council"; else echo "morning"; fi; }
# meme feature, cluster change entre-temps: le compteur NE se reinitialise PAS
eq "cap: gen1 -> fix"      "$(_route "$(_gen depot-item)")" "fix"
eq "cap: gen2 -> fix"      "$(_route "$(_gen depot-item)")" "fix"
eq "cap: gen3 -> council"  "$(_route "$(_gen depot-item)")" "council"
eq "cap: gen4 -> morning"  "$(_route "$(_gen depot-item)")" "morning"
# une AUTRE feature garde son propre compteur (independant)
eq "cap: autre feature gen1" "$(_route "$(_gen referentiel-front)")" "fix"
eq "cap: cable dans driver (v680: chemin persistant hors worktree)" "$(grep -c 'loop/lot-gen' loop/loop-overnight.sh)" "2"
rm -rf "$LG"


# v6.28.1: maker-perf porte l'etat spec, l'A/B devient lisible
MPS="$(mktemp)"
printf 'r\tc1\thermes\tqwen\t600\tGREEN\tspec=0\nr\tc2\thermes\tqwen\t480\tGREEN\tspec=1\n' > "$MPS"
OUT="$(python3 - "$MPS" <<'PYP'
import sys,collections,statistics
g=collections.defaultdict(list)
for l in open(sys.argv[1]):
    r=l.rstrip("\n").split("\t")
    if len(r)>=7 and r[5]=="GREEN": g[r[2]+" "+r[6]].append(int(r[4]))
for k in sorted(g): print(k, int(statistics.median(g[k])))
PYP
)"
eq "spec-ab: sans spec tracee"  "$(printf '%s' "$OUT" | grep -c 'spec=0 600')" "1"
eq "spec-ab: avec spec tracee"  "$(printf '%s' "$OUT" | grep -c 'spec=1 480')" "1"
eq "spec-ab: colonne au perf"   "$(grep -c 'spec=\${LOOP_SPECULATIVE' loop/loop-overnight.sh)" "1"
rm -f "$MPS"


# v6.29: le bench speculatif (outillage MLX local, non seme aux loops frontier: tests skippes si absent)
if [ -f loop/spec-bench.sh ]; then
eq "bench: script present"       "$([ -x loop/spec-bench.sh ] && echo oui)" "oui"
eq "bench: charge sans spec (A)" "$(grep -c 'lms load "$MLXM" --context-length 65536 --parallel 1 -y' loop/spec-bench.sh)" "1"
eq "bench: charge avec draft (B)" "$(grep -c 'speculative-draft-simple --speculative-draft-model' loop/spec-bench.sh)" "1"
eq "bench: verdict ratio"        "$(grep -c 'gain decode' loop/spec-bench.sh)" "1"
fi


# v6.30: garde memoire, seuil respecte
. "$PWD/loop/mem-guard.sh" 2>/dev/null
AV="$(mem_available_gb)"
eq "mem: lecture numerique"   "$([ "$AV" -ge 0 ] 2>/dev/null && echo oui)" "oui"
eq "mem: refuse si trop haut"  "$(mem_guard 9999 2>/dev/null; echo $?)" "1"
eq "mem: passe si trivial"     "$(mem_guard 0 >/dev/null 2>&1; echo $?)" "0"
[ -f loop/spec-bench.sh ] && { eq "mem: bench garde cablee"   "$(grep -c 'mem_guard 24' loop/spec-bench.sh)" "1"
eq "mem: bench refuse batterie" "$(grep -c 'on_ac_power ||' loop/spec-bench.sh)" "1"; }
eq "mem: driver garde cablee"  "$(grep -c 'mem_guard \"\${LOOP_MEM_NEED' loop/loop-overnight.sh)" "1"


# v6.32: loop-init seme la loi COMPLETE + pack generique (pas d'identite projet)
LI2="$(mktemp -d)"; git -C "$LI2" init -q
bash loop/loop-init.sh "$LI2" --stack angular-spring >/dev/null 2>&1
eq "seed: mem-guard seme"        "$([ -f "$LI2/loop/mem-guard.sh" ] && echo oui)" "oui"
eq "seed: maquette-fidelity seme" "$([ -f "$LI2/loop/maquette-fidelity.sh" ] && echo oui)" "oui"
eq "seed: morning-digest seme"   "$([ -f "$LI2/loop/morning-digest.sh" ] && echo oui)" "oui"
eq "seed: zero domaine en dur"   "$(grep -cE '[A-Z][a-z]+Entity' "$LI2/loop/stack.sh")" "0"
eq "seed: placeholder brief"     "$([ "$(grep -c 'A REMPLIR' "$LI2/loop/stack.sh")" -ge 2 ] && echo oui)" "oui"
eq "pack: generique sans domaine en dur" "$(grep -cE '[A-Z][a-z]+Entity' loop/stack.d/angular-spring.sh)" "0"
rm -rf "$LI2"


# v6.36: swap_local, un seul modele local resident (branchement correct par famille)
_swapbranch(){ case "$1" in *mlx*|*MLX*) echo "keep-mlx";; *) echo "swap-out-mlx";; esac; }
eq "swap: maker MLX garde MLX"       "$(_swapbranch qwen3-coder-30b-a3b-instruct-mlx)" "keep-mlx"
eq "swap: maker ornith decharge MLX" "$(_swapbranch ornith-cc)" "swap-out-mlx"
eq "swap: maker qwen3:14b decharge MLX" "$(_swapbranch qwen3:14b)" "swap-out-mlx"
eq "swap: fonction cablee"           "$(grep -c '^swap_local()' loop/loop-overnight.sh)" "1"
eq "swap: appele avant le cycle"     "$(grep -c 'swap_local "$LOOP_MAKER"' loop/loop-overnight.sh)" "1"
eq "swap: gate MLX-only (swap+police)" "$(grep -c 'LOOP_MLX:-0}" = 1 ] || return 0' loop/loop-overnight.sh)" "2"
eq "swap: keeper pid capture"        "$(grep -c 'MLX_KEEPER_PID=\$!' loop/loop-overnight.sh)" "2"


# v6.37: sous LOOP_MLX=1, DEFAULT_MAKER = nom MLX (pas le nom ollama)
eq "mlx-maker: DEFAULT_MAKER=MLXM"    "$(grep -c 'DEFAULT_MAKER="$MLXM"' loop/loop-overnight.sh)" "1"
eq "mlx-maker: apres MLX ready"       "$(awk '/MLX ready \(loaded/{f=NR} /DEFAULT_MAKER="\$MLXM"/{if(NR>f && f>0) print "ok"}' loop/loop-overnight.sh | head -1)" "ok"


# v6.38: dedup semis universelle + garde infra qui sonde
SD38="$(mktemp -d)"; mkdir -p "$SD38/q"
base_name(){ local n="$1" p; while true; do p="$n"; n="${n#zz-[DEH]-}"; n="${n#00-F[0-9]-}"; [ "$n" = "$p" ] && break; done; echo "$n"; }
# simulateur de la condition seed-dedup: sans probe + vert en historique => drop
_hist="feat: 91-fix-critical [loop cycle 2]
feat: 06-decision-api [loop cycle 1]"
_seed_drop(){ # $1=nom $2=a-probe(0/1) -> drop/keep
  local probed="$2"
  if [ "$probed" = "0" ] && printf '%s\n' "$_hist" | grep -q "^feat: $(base_name "$1") \[loop"; then echo drop; else echo keep; fi
}
eq "dedup38: vert sans probe -> drop"  "$(_seed_drop 91-fix-critical 0)" "drop"
eq "dedup38: vert AVEC probe -> keep"  "$(_seed_drop 06-decision-api 1)" "keep"
eq "dedup38: pas vert -> keep"         "$(_seed_drop 26-position-client-front 0)" "keep"
eq "dedup38: zz-D vert sans probe -> drop" "$(_seed_drop zz-D-91-fix-critical 0)" "drop"
rm -rf "$SD38"
# structure driver: les deux fixes en place
eq "v638: dedup aux 2 sites de semis (v683: +variante reparation)" "$(grep -c 'seed-dedup:' loop/loop-overnight.sh)" "4"
eq "v638: sonde avant infra"          "$(grep -c 'if model_alive; then' loop/loop-overnight.sh)" "1"
eq "v638: noop-done branche"          "$(grep -c 'NOOP-DONE' loop/loop-overnight.sh)" "3"
eq "v638->639: muet ne stoppe plus"   "$(grep -c 'muet x3 sur .NAME: defer' loop/loop-overnight.sh)" "1"
eq "v638: model_alive definie"        "$(grep -c '^model_alive()' loop/loop-overnight.sh)" "1"


# v6.39: le loop ne s'arrete JAMAIS avant la deadline, il s'auto-repare
eq "v639: zero break infra"       "$(grep -c 'INFRA STOP: model layer unresponsive' loop/loop-overnight.sh)" "0"
eq "v639: zero break mute"        "$(grep -c 'ARRET: maker muet' loop/loop-overnight.sh)" "0"
eq "v639: breaker continue"       "$(grep -c 'run poursuivi' loop/loop-overnight.sh)" "1"
eq "v639: heal defini"            "$(grep -c '^heal_model_layer()' loop/loop-overnight.sh)" "1"
eq "v639: heal appele avant pause" "$(grep -c 'if heal_model_layer; then' loop/loop-overnight.sh)" "1"
eq "v639: profil regen auto"      "$(grep -c 'regeneration du profil hermes (auto-reparation)' loop/loop-overnight.sh)" "1"
eq "v639: mute defer pas stop"    "$(grep -c 'MUET x3 (modele sain), defere' loop/loop-overnight.sh)" "1"
eq "v639: mem_police definie"     "$(grep -c '^mem_police()' loop/loop-overnight.sh)" "1"
eq "v639: mem_police par tour"    "$(grep -c '^  mem_police ' loop/loop-overnight.sh)" "1"
eq "v639: pause bornee deadline"  "$(grep -c 'deadline proche, fin de fenetre' loop/loop-overnight.sh)" "1"
# invariant: les seuls break restants = deadline, STOP, slack, queue-complete (fins legitimes)
eq "v639: zero arret interdit" "$(grep -ciE 'Stopped early|halted early|Arret bruyant|Run halted' loop/loop-overnight.sh)" "0"


# v6.39.1: le ctx du profil hermes correspond au ctx de charge MLX (32768 = 32768)
# v6.42 remplace l'alignement 32768 (v6.39.1) par 65536: le plancher Hermes est 64000,
# l'alignement doit se faire vers le HAUT. La loi reste: profil declare == charge reelle.
eq "ctx: profil aligne sur la charge" "$(grep -c '"context_length": 65536' loop/setup-hermes-profile.sh)" "1"
eq "ctx: charge MLX a 65536"          "$([ "$(grep -c 'context-length 65536' loop/loop-overnight.sh)" -ge 2 ] && echo oui)" "oui"


# v6.39.2: env de lancement persiste pour le resurrecteur + famille mlx
esc_family2(){ case "$1" in *mlx*|*MLX*) echo mlx;; claude-*|*opus*|*sonnet*|*haiku*) echo claude;; codex|gpt-*|o1-*|o3-*|o4-*) echo codex;; *) echo hermes;; esac; }
eq "env: tag mlx sous run ollama ignore" "$([ "$(esc_family2 qwen3-coder-30b-a3b-instruct-mlx)" = "$(esc_family2 ornith-cc)" ] && echo meme || echo differe)" "differe"
eq "env: NIGHT-ENV ecrit au lancement"   "$([ "$(grep -c 'NIGHT-ENV' loop/loop-overnight.sh)" -ge 1 ] && echo oui)" "oui"
eq "env: resurrect source NIGHT-ENV"     "$(grep -c 'NIGHT-ENV' loop/resurrect.sh)" "1"


# v6.40: l'effort claude est explicite et mesure (plus d'heritage global cache)
eq "effort: flag explicite maker"  "$(grep -c '\-\-effort "${LOOP_CLAUDE_EFFORT:-medium}"' loop/run-cycle.sh)" "1"
eq "effort: trace dans maker-perf" "$(grep -c 'LOOP_MAKER@\${LOOP_CLAUDE_EFFORT' loop/loop-overnight.sh)" "1"


# v6.41: socle front mecanique + defer-hard repete -> decoupage
FS="$(mktemp -d)"; mkdir -p "$FS/pages" "$FS/q"
# simulateur de la condition: pages<2 + carte front en file => injecter + DEPENDS
_needs_scaffold(){ local p="$1" fc="$2"; [ "$p" -lt 2 ] && [ -n "$fc" ] && echo oui || echo non; }
eq "scaffold: front vide + carte front = injecte" "$(_needs_scaffold 0 "50-ecran.md")" "oui"
eq "scaffold: front peuple = non"                 "$(_needs_scaffold 3 "50-ecran.md")" "non"
eq "scaffold: pas de carte front = non"           "$(_needs_scaffold 0 "")" "non"
# DEPENDS ajoute seulement si absent
printf 'USE CASE x\nSCOPE: front\n' > "$FS/q/50-a.md"
grep -q '^DEPENDS:' "$FS/q/50-a.md" || printf 'DEPENDS: 05-front-scaffold\n' >> "$FS/q/50-a.md"
grep -q '^DEPENDS:' "$FS/q/50-a.md" || printf 'DEPENDS: 05-front-scaffold\n' >> "$FS/q/50-a.md"
eq "scaffold: DEPENDS injecte une fois" "$(grep -c '^DEPENDS: 05-front-scaffold' "$FS/q/50-a.md")" "1"
# compteur defer-hard: 2e -> park
_dh(){ local f="$FS/$1.count"; local c=$(( $(cat "$f" 2>/dev/null || echo 0) + 1 )); echo "$c" > "$f"; [ "$c" -ge 2 ] && echo park || echo tail; }
eq "deferhard: 1er = tail"  "$(_dh cardX)" "tail"
eq "deferhard: 2e = park"   "$(_dh cardX)" "park"
rm -rf "$FS"
# structure driver
eq "v641: fonction scaffold"        "$(grep -c '^ensure_front_scaffold()' loop/loop-overnight.sh)" "1"
eq "v641: appelee aux 2 semis"      "$([ "$(grep -cE '^ensure_front_scaffold( |$)' loop/loop-overnight.sh)" -ge 2 ] && echo oui)" "oui"
eq "v641: park au 2e defer-hard"    "$(grep -c 'PARK+SPLIT' loop/loop-overnight.sh)" "1"
eq "v641: carto decoupe les parkees" "$(grep -c 'CARTES PARKEES A DECOUPER' loop/loop-overnight.sh)" "1"
eq "v641: regle absolue pages"      "$(grep -c 'REGLE ABSOLUE SI PAGES_N' loop/loop-overnight.sh)" "1"
# v6.41.1 GARDE GENERALISEE (3e recidive de la classe base_name): toute fonction du
# driver appelee au top-level doit etre definie AVANT son premier appel.
for _fn in base_name ensure_front_scaffold model_alive swap_local heal_model_layer mem_police esc_family consume_feedback usage_watch print_contract gate_selftest sig_of_last_cycle autopsy preflight maker_ping quota_pause pick_card build_coverage route_failure; do
  _FD="$(grep -n "^${_fn}()" loop/loop-overnight.sh 2>/dev/null | head -1 | cut -d: -f1)"
  [ -z "$_FD" ] && continue
  _FC="$(grep -nE "^[^#]*(^|[ \"\$(])${_fn}([ \"]|\$)" loop/loop-overnight.sh 2>/dev/null | grep -v "${_fn}()" | head -1 | cut -d: -f1)"
  [ -z "$_FC" ] && continue
  eq "ordre: ${_fn} defini avant appel" "$([ "$_FD" -lt "$_FC" ] && echo oui)" "oui"
done

# ---- v6.42: contexte 65536 coherent + jamais de nuit sur profil user sous MLX ----
# Nuit blanche du 08/07 (96 cycles, green=0): plancher Hermes 64000 vs profil 32768 ->
# profil loop inadoptable -> profil user -> HTTP 404 sur le nom MLX -> "muet" en boucle.
eq "v642: plus aucun load 32768"    "$(grep -c 'context-length 32768' loop/loop-overnight.sh)" "0"
eq "v642: load 65536 partout (>=4)" "$([ "$(grep -c 'context-length 65536' loop/loop-overnight.sh)" -ge 4 ] && echo oui)" "oui"
eq "v642: profil declare 65536"     "$(grep -c '"context_length": 65536' loop/setup-hermes-profile.sh)" "1"
eq "v642: plancher 64000 documente" "$(grep -c 'minimum 64' loop/setup-hermes-profile.sh)" "1"
eq "v642: degradation swap ollama"  "$(grep -c 'DEGRADATION SWAP' loop/loop-overnight.sh)" "1"
eq "v642: adoption re-essayee x3"   "$(grep -c '_ptry' loop/loop-overnight.sh | awk '{print ($1>=3)?"oui":"non"}')" "oui"
eq "v642: re-adoption apres regen (>=3 exports)" "$([ "$(grep -c 'export LOOP_HERMES_HOME' loop/loop-overnight.sh)" -ge 3 ] && echo oui)" "oui"
eq "v642: classif routage API"      "$([ "$(grep -c 'API call failed' loop/loop-overnight.sh)" -ge 1 ] && echo oui)" "oui"
eq "v642: plafond reparations routage" "$([ "$(grep -c 'route_c' loop/loop-overnight.sh)" -ge 3 ] && echo oui)" "oui"
# Le keeper re-epingle le modele toutes les 60s: s'il porte un autre contexte que le
# driver, il DEFAIT le fix une minute apres le chargement (piege attrape le 08/07 au
# balayage residus). Loi: keeper, driver et profil portent LE MEME contexte.
_CTX_DRV="$(grep -o 'context-length [0-9]*' loop/loop-overnight.sh | sort -u | head -1 | awk '{print $2}')"
_CTX_KPR="$(grep -o 'context-length [0-9]*' loop/mlx-keeper.sh | sort -u | head -1 | awk '{print $2}')"
_CTX_PRF="$(grep -o '"context_length": [0-9]*' loop/setup-hermes-profile.sh | head -1 | grep -o '[0-9]*')"
eq "v642: keeper aligne sur driver"  "$_CTX_KPR" "$_CTX_DRV"
eq "v642: profil aligne sur driver"  "$_CTX_PRF" "$_CTX_DRV"
eq "v642: un seul ctx dans le driver" "$(grep -o 'context-length [0-9]*' loop/loop-overnight.sh | sort -u | wc -l | tr -d ' ')" "1"
eq "v642: ctx >= plancher hermes 64000" "$([ "${_CTX_DRV:-0}" -ge 64000 ] && echo oui)" "oui"
eq "v642: seuil downgrade keeper 60000" "$(grep -c 'lt 60000' loop/mlx-keeper.sh)" "1"

# ---- v6.43 GARDE ANTI-FUITE: la loi n'execute aucune commande stack en dur ----
# Question utilisateur du 08/07: "si on fixe Angular, ne retrouvera-t-on pas le meme
# probleme sur flutter/php/.net?". Reponse structurelle: tout token stack dans la LOI
# hors ligne "# stack-default" (defaut contractuel) et hors commentaire pur CASSE ce
# test. Une fuite ne peut plus se reintroduire silencieusement.
_LEAK=0
for _tok in 'npm ci' 'npx ng' 'npx playwright' 'spring-boot:run' 'mvnw' 'sdkman' 'flutter pub' 'dotnet restore' 'composer install'; do
  for _lf in loop/loop-overnight.sh loop/run-cycle.sh loop/e2e.sh loop/verify.sh; do
    _N="$(grep -n -- "$_tok" "$_lf" 2>/dev/null | grep -v 'stack-default' | grep -vE '^[0-9]+:[[:space:]]*#' | wc -l | tr -d ' ')"
    [ "$_N" -gt 0 ] && { _LEAK=$((_LEAK+_N)); echo "  FUITE STACK: '$_tok' dans $_lf (x$_N, hors stack-default)"; }
  done
done
eq "v643: zero fuite stack dans la loi" "$_LEAK" "0"
eq "v643: install contractuel (driver)"   "$([ "$(grep -c 'STACK_INSTALL_CMD' loop/loop-overnight.sh)" -ge 1 ] && echo oui)" "oui"
eq "v643: gate front contractuel"         "$([ "$(grep -c 'GATE_FRONT_CMD' loop/run-cycle.sh)" -ge 2 ] && echo oui)" "oui"
eq "v643: gate back contractuel"          "$([ "$(grep -c 'GATE_BACK_CMD' loop/run-cycle.sh)" -ge 2 ] && echo oui)" "oui"
eq "v643: gate garde -d (api-only)"       "$(grep -c -- '-d "$ROOT/$FRONT_DIR"' loop/run-cycle.sh)" "1"
eq "v643: hint outillage contractuel"     "$([ "$(grep -c 'TOOLCHAIN_HINT' loop/run-cycle.sh)" -ge 2 ] && echo oui)" "oui"
eq "v643: env maker contractuel"          "$([ "$(grep -c 'stack_maker_env' loop/run-cycle.sh)" -ge 2 ] && echo oui)" "oui"
eq "v643: socle front garde ARCH_PROFILE" "$(grep -c 'api-only|lib|cli' loop/loop-overnight.sh)" "1"
eq "v643: yeux exts contractuelles"       "$([ "$(grep -c 'EYE_SRC_EXTS' loop/loop-overnight.sh)" -ge 1 ] && echo oui)" "oui"
eq "v643: run-cycle defauts en forme :-"  "$(grep -c 'BACK_DIR="${BACK_DIR:-' loop/run-cycle.sh)" "1"
eq "v643: e2e sentinel contractuel"       "$([ "$(grep -c 'E2E_SENTINEL' loop/e2e.sh)" -ge 1 ] && echo oui)" "oui"
eq "v643: spec contrat presente"          "$([ -f loop/STACK-CONTRACT.md ] && echo oui)" "oui"
eq "v643: spec semee par loop-init"       "$([ "$(grep -c 'STACK-CONTRACT.md' loop/loop-init.sh)" -ge 1 ] && echo oui)" "oui"
eq "v643: conformite contrat a l'init"    "$([ "$(grep -c 'contrat stack v2' loop/loop-init.sh)" -ge 1 ] && echo oui)" "oui"
eq "v643: pack angular-spring v2"         "$(grep -c '^ARCH_PROFILE=' loop/stack.d/angular-spring.sh)" "1"
# v6.46: sur un semis vierge, stack.sh est un SQUELETTE a remplir (pas v2-complet); le
# test exige v2 OU squelette explicite, jamais un stack.sh muet entre les deux.
eq "v643: stack.sh du projet en v2"                "$({ grep -q '^ARCH_PROFILE=' loop/stack.sh || grep -q 'A REMPLIR' loop/stack.sh; } && echo oui)" "oui"
eq "v643: verify tests contractuels"      "$([ "$(grep -c 'VERIFY_BACK_CMD' loop/verify.sh)" -ge 2 ] && echo oui)" "oui"
eq "v643: verify boot contractuel"        "$([ "$(grep -c 'BOOT_BACK_CMD' loop/verify.sh)" -ge 2 ] && echo oui)" "oui"
eq "v643: verify sante contractuelle"     "$([ "$(grep -c 'HEALTH_OK_PATTERN' loop/verify.sh)" -ge 2 ] && echo oui)" "oui"
eq "v643: verify garde -d front"          "$(grep -c -- '-d "$ROOT/$FRONT_DIR"' loop/verify.sh)" "1"
# v6.43.1 (observation pilote run 11:38): socle du carto reconnu, jamais de doublon
eq "v6431: dedup socle carto"             "$(grep -c 'SOCLE FRONT du carto detecte' loop/loop-overnight.sh)" "1"
eq "v6431: depends vise le socle trouve"  "$([ "$(grep -c 'DEPENDS: %s' loop/loop-overnight.sh)" -ge 1 ] && echo oui)" "oui"
eq "v6431: appel apres refill carto (3 semis)" "$([ "$(grep -cE '^(  )?ensure_front_scaffold( |$)' loop/loop-overnight.sh)" -ge 3 ] && echo oui)" "oui"
# v6.45 remplace l'expansion %% directe (crash set -u si var absente, BUG A pilote)
eq "v6431: probe socle sans .ts en dur"   "$(grep -c '_ext="${EYE_SRC_EXTS:-' loop/loop-overnight.sh)" "1"
eq "v645: plus d expansion %% nue"        "$(grep -c 'EYE_SRC_EXTS%%' loop/loop-overnight.sh)" "0"
eq "v645: defauts v2 poses par la loi"    "$([ "$(grep -c 'set-u-crasher' loop/loop-overnight.sh)" -ge 1 ] && echo oui)" "oui"
# BUG B: GSTORE defini en tete, une seule definition, avant tout usage
_GD="$(grep -n '^GSTORE=' loop/distill.sh | head -1 | cut -d: -f1)"
_GU="$(grep -n '\$GSTORE' loop/distill.sh | head -1 | cut -d: -f1)"
eq "v645: GSTORE une seule definition"    "$(grep -c '^GSTORE=' loop/distill.sh)" "1"
eq "v645: GSTORE defini avant usage"      "$([ -n "$_GD" ] && [ -n "$_GU" ] && [ "$_GD" -lt "$_GU" ] && echo oui)" "oui"
# Quota: le cerveau des cartes bascule de famille (carto_llm), codex en dur seulement au checker/lot
eq "v645: carto_llm definie"              "$(grep -c '^carto_llm()' loop/loop-overnight.sh)" "1"
eq "v645: carto_llm cablee aux 3 sites"   "$([ "$(grep -c 'carto_llm [0-9]' loop/loop-overnight.sh)" -ge 3 ] && echo oui)" "oui"
# <=3: revue de lot (doctrine juge) + interne carto_llm + ping preflight v6.46
eq "v645: codex en dur borne (lot + fallbacks)" "$(grep -c 'codex exec' loop/loop-overnight.sh | awk '{print ($1<=4)?"oui":"non"}')" "oui"
eq "v645: chair carto contractuel"        "$([ "$(grep -c 'LOOP_CARTO_CHAIR' loop/loop-overnight.sh)" -ge 2 ] && echo oui)" "oui"
# ---- v6.45.1 BUG C (pilote, 9 faux REDCOMPILE): re-source + variable vide ----
# Chaque script de loi source le contrat UNE seule fois (en tete, avant ses defauts);
# et aucun contrat ne livre une commande VIDE (omettre = defaut loi).
for _sf in run-cycle.sh loop-overnight.sh verify.sh e2e.sh distill.sh; do
  eq "v6451: $_sf source le contrat 1x" "$(grep -cE '^[^#]*\. .*stack\.sh' "loop/$_sf")" "1"
done
eq "v6451: aucun _CMD='' dans les contrats" "$(grep -cE "^[A-Z_]*_CMD=''" loop/stack.sh loop/stack.d/*.sh | awk -F: '{s+=$NF} END{print s+0}')" "0"
eq "v6451: doctrine omission documentee"   "$([ "$(grep -c 'OMETTRE' loop/STACK-CONTRACT.md)" -ge 1 ] && echo oui)" "oui"
eq "v6451: gate back garde son defaut"     "$(grep -c 'GATE_BACK_CMD="${GATE_BACK_CMD:-' loop/run-cycle.sh)" "1"
# v6.43.2 (diagnostic pilote, 5 echecs socle): remplacer le shell casse le spec par
# defaut; les probes socle ne doivent JAMAIS exiger la suite unitaire du squelette.
eq "v6432: regle probes socle au carto"   "$(grep -c 'PROBES DU SOCLE' loop/loop-overnight.sh)" "1"
eq "v6432: carte socle exige maj des specs" "$([ "$(grep -c 'defaut du squelette' loop/loop-overnight.sh)" -ge 3 ] && echo oui)" "oui"
eq "v6432: hint spec par defaut"          "$([ -f loop/hints.d/23-default-spec-shell.hint ] && echo oui)" "oui"
eq "v6432: probes socle injectee sans test unitaire" "$(sed -n '/<<SCAF/,/^SCAF$/p' loop/loop-overnight.sh | grep -c 'PROBE.*npm test\|PROBE.*flutter test\|PROBE.*mvn test')" "0"
# v6.44 (diagnostic corrige pilote: LE mur front = probe exigeant un spec unitaire
# maker-authored sous revert atomique): regle carto ecrans, lint au semis, gabarit hint.
eq "v644: regle probes ecrans au carto"   "$(grep -c "PROBES DES CARTES D'ECRAN FRONT" loop/loop-overnight.sh)" "1"
eq "v644: regle probes au split-parked"   "$(grep -c 'REGLE PROBES (cartes front)' loop/loop-overnight.sh)" "1"
eq "v644: lint probe unitaire au semis"   "$([ "$(grep -c 'WARN probe-lint' loop/loop-overnight.sh)" -ge 3 ] && echo oui)" "oui"
eq "v644: gabarit testbed en hint"        "$([ -f loop/hints.d/24-testbed-spec.hint ] && echo oui)" "oui"
eq "v644: gabarit = config qui passe"     "$([ "$(grep -c 'provideHttpClientTesting' loop/hints.d/24-testbed-spec.hint)" -ge 2 ] && echo oui)" "oui"

# v6.46 (cahier des charges pilote, 6 points): preflight de chaine, breaker a
# signatures, autopsie 0-vert, smoke de release a execution reelle, couche modele inerte.
eq "v646: preflight AVANT phase0"         "$([ "$(grep -n '^if ! preflight' loop/loop-overnight.sh | head -1 | cut -d: -f1)" -lt "$(grep -n 'phase0_review "initial"' loop/loop-overnight.sh | head -1 | cut -d: -f1)" ] && echo oui)" "oui"
eq "v646: refus preflight = exit 2 + tel" "$(sed -n '/^if ! preflight/,/^fi$/p' loop/loop-overnight.sh | grep -c 'notify_phone\|exit 2')" "2"
eq "v646: DRYBOOT sort apres preflight"   "$(grep -c 'LOOP_DRYBOOT:-0.*= 1 \]' loop/loop-overnight.sh)" "1"
eq "v646: contrat imprime avec provenance" "$(grep -c "src=\"stack.sh\" || src=\"defaut-loi\"" loop/loop-overnight.sh)" "1"
eq "v646: selftest refuse gate VIDE"      "$(sed -n '/^gate_selftest(){/,/^}/p' loop/loop-overnight.sh | grep -c 'commande de gate VIDE')" "1"
eq "v646: selftest = memes defauts que run-cycle" "$([ "$(grep -c 'test-compile}"' loop/loop-overnight.sh)" -ge 1 ] && [ "$(grep -c 'npx ng build}"' loop/loop-overnight.sh)" -ge 1 ] && echo oui)" "oui"
eq "v646: breaker x3 meme signature"      "$(grep -c 'SIG_N:-0}" -ge 3' loop/loop-overnight.sh)" "1"
eq "v646: breaker juge par selftest, pas d'accusation" "$(sed -n '/BREAKER: 3 echecs/,/^    fi$/p' loop/loop-overnight.sh | grep -c 'gate_selftest')" "2"
eq "v646: autopsie cablee au 0-vert"      "$(grep -c '_AUT="$(autopsy)"' loop/loop-overnight.sh)" "1"
eq "v646: verify final logue (plus de /dev/null)" "$(grep -c 'verify-final-' loop/loop-overnight.sh)" "1"
eq "v646: smoke de release existe"        "$([ -f loop/tests/release-smoke.sh ] && echo oui)" "oui"
eq "v646: smoke verrouille (accord proprietaire)" "$(grep -c 'LOOP_SMOKE_ACK' loop/tests/release-smoke.sh)" "2"
eq "v646: smoke force couche modele inerte" "$(grep -c 'export LOOP_NO_LOCAL_LLM=1' loop/tests/release-smoke.sh)" "1"
eq "v646: verrou GPU sur les 3 organes modele" "$([ "$(grep -c 'LOOP_NO_LOCAL_LLM:-0}" = 1 \] && return 0' loop/loop-overnight.sh)" -ge 3 ] && echo oui)" "oui"
eq "v646: stub exige LOOP_MAKER_STUB explicite" "$(grep -c 'LOOP_MAKER_STUB:?' loop/run-cycle.sh)" "1"
eq "v646: council a un interrupteur"      "$(grep -c 'LOOP_COUNCIL:-1' loop/council.sh)" "1"
eq "v646: council shebang en ligne 1"     "$(head -1 loop/council.sh)" "#!/usr/bin/env bash"
eq "v646: carto debrayable (smoke)"       "$(grep -c 'LOOP_CARTO:-1' loop/loop-overnight.sh)" "1"
eq "v646: verify tue l'ARBRE du boot"     "$(grep -c 'pkill -P "$BOOT_PID"' loop/verify.sh)" "1"
eq "v646: verify vit sans FRONT_DIR"      "$(grep -c 'SCOPE" != "back" \] && \[ -n "$FRONT_DIR"' loop/verify.sh)" "1"

# v6.47 (rapport pilote run 16:24: quota mort en run => 24 HARD-FAIL 0m sur la meme
# carte; socle jamais servi en 3 runs; couverture-opinion 0/20 => doublons): sentir
# avant d'agir. Quota=sommeil, muet=stop-the-line, file par valeur, couverture=fait git,
# cooldown anti-marteau, ceinture de routage, rapport agrege.
eq "v647: sonde maker par famille"        "$(sed -n '/^maker_ping(){/,/^}/p' loop/loop-overnight.sh | grep -c 'codex)\|claude)\|stub)')" "3"
eq "v647: fast-fail x2 => sonde, pas la carte" "$(grep -c 'FF_N:-0}" -ge 2 \] && ! maker_ping' loop/loop-overnight.sh)" "1"
eq "v647: quota_pause lit l'heure de reset" "$([ "$(sed -n '/^quota_pause(){/,/^}/p' loop/loop-overnight.sh | grep -c 'try again at')" -ge 1 ] && echo oui)" "oui"
eq "v647: quota_pause borne par la deadline" "$(sed -n '/^quota_pause(){/,/^}/p' loop/loop-overnight.sh | grep -c 'deadline - 700')" "1"
eq "v647: quota_pause re-sonde et reprend tot" "$(sed -n '/^quota_pause(){/,/^}/p' loop/loop-overnight.sh | grep -c 'maker_ping &&')" "1"
eq "v647: cooldown ecrit au requeue zz-E" "$(grep -c 'cooldown/zz-E-$(base_name "$2").md.cd' loop/loop-overnight.sh)" "1"
eq "v647: pick_card saute les cooldowns"  "$(sed -n '/^pick_card(){/,/^}/p' loop/loop-overnight.sh | grep -c 'cooldown')" "2"
eq "v647: pick_card ordonne par VALUE"    "$([ "$(sed -n '/^pick_card(){/,/^}/p' loop/loop-overnight.sh | grep -c 'P\[0-3\]')" -ge 1 ] && echo oui)" "oui"
eq "v647: le selecteur EST pick_card"     "$(grep -c 'CARD="$(pick_card)"' loop/loop-overnight.sh)" "1"
eq "v647: tout-cooldown = attente, pas fin" "$(grep -c 'toutes les cartes en cooldown' loop/loop-overnight.sh)" "1"
eq "v647: ceinture routage (jamais 24x)"  "$(grep -c 'ROUTAGE RATE' loop/loop-overnight.sh)" "2"
eq "v647: socle injecte porte VALUE P1"   "$(sed -n '/<<SCAF/,/^SCAF$/p' loop/loop-overnight.sh | grep -c '^VALUE: P1')" "1"
eq "v647: couverture mecanique = fait git" "$(sed -n '/^build_coverage(){/,/^}/p' loop/loop-overnight.sh | grep -c 'git log --format=%s')" "1"
eq "v647: interdit doublon dans le carto" "$(grep -c 'INTERDIT (v6.47' loop/loop-overnight.sh)" "1"
eq "v647: probes doivent echouer a la naissance" "$(grep -c 'PROBEs qui ECHOUENT' loop/loop-overnight.sh)" "1"
eq "v647: regle VALUE au carto"           "$(grep -c "VALUE: P1|P2|P3" loop/loop-overnight.sh)" "2"
eq "v647: rapport agrege les echecs x3"   "$(grep -c 'Echecs agreges' loop/loop-overnight.sh)" "1"
eq "v647: autopsie classe le quota"       "$(grep -c 'QUOTA maker epuise en run' loop/loop-overnight.sh)" "1"

# v6.48 (remontee 20 pilote, l'angle mort le plus subtil: le probe rg-OU ment, un
# token generique deja present => AUTODONE d'ecrans jamais construits): probes en ET.
eq "v648: semantique ET au bloc ecrans"   "$(grep -c 'SEMANTIQUE DES PROBES rg' loop/loop-overnight.sh)" "1"
eq "v648: socle carto en ET"              "$(grep -c 'PROBES DU SOCLE, EN ET' loop/loop-overnight.sh)" "1"
eq "v648: decoupage en ET"                "$(grep -c 'PROBES EN ET' loop/loop-overnight.sh)" "1"
eq "v648: token specifique exige (2 blocs)" "$(grep -c 'token SPECIFIQUE' loop/loop-overnight.sh)" "2"
eq "v648: lint anti probe-OU au semis (v671: elargi + effet reel)" "$(grep -c 'porte un probe OU' loop/loop-overnight.sh)" "1"
eq "v648: socle injecte, seuil pages dynamique" "$(sed -n '/<<SCAF/,/^SCAF$/p' loop/loop-overnight.sh | grep -c 'ge \$(( pages + 1 ))')" "1"
eq "v648: socle injecte, 3 probes en ET"  "$(sed -n '/<<SCAF/,/^SCAF$/p' loop/loop-overnight.sh | grep -c '^PROBE')" "3"

# v6.48.1 (lancement 09/07: JAVA_HOME absent d'un shell non-interactif => preflight
# refusait sur l'arbre vert): l'env outillage est pose au TOP-LEVEL, avant gate_selftest.
eq "v6481: toolchain env au top-level"    "$(grep -c 'stack_maker_env >/dev/null 2>&1; then stack_maker_env' loop/loop-overnight.sh)" "1"
eq "v6481: JAVA_HOME pose avant le gate"  "$([ "$(grep -n 'export JAVA_HOME="$_J"' loop/loop-overnight.sh | head -1 | cut -d: -f1)" -lt "$(grep -n '^gate_selftest(){' loop/loop-overnight.sh | cut -d: -f1)" ] && echo oui)" "oui"

# v6.49 (regression MLX du 09/07: base hermes bascule sur provider moa, pyyaml absent au
# reboot, LOOP_MLX_MODEL/URL jamais exportes => profil inadoptable => degradation ollama):
# provider force custom sous MLX, python venv hermes pour l'overlay, exports alignes,
# refus ollama par defaut, preflight local via hermes.
eq "v649: provider MLX force (pas d'heritage moa)" "$(grep -c 'LOOP_MLX_PROVIDER", "custom"' loop/setup-hermes-profile.sh)" "1"
eq "v649: overlay via python venv hermes"  "$(grep -c 'HERMES_PY="$HOME/.hermes/hermes-agent/venv/bin/python3"' loop/setup-hermes-profile.sh)" "1"
eq "v649: overlay teste pyyaml avant usage" "$(grep -c "\"\$HERMES_PY\" -c 'import yaml'" loop/setup-hermes-profile.sh)" "1"
eq "v649: smoke MLX defaut = nom charge"   "$(grep -c 'LOOP_MLX_MODEL:-qwen3-coder-30b-a3b-instruct-mlx' loop/setup-hermes-profile.sh)" "1"
eq "v649: driver exporte LOOP_MLX_MODEL"   "$(grep -c 'export LOOP_MLX_MODEL="$MLXM"' loop/loop-overnight.sh)" "1"
eq "v649: driver exporte LOOP_MLX_URL"     "$(grep -c 'export LOOP_MLX_URL=' loop/loop-overnight.sh)" "1"
eq "v649: ollama fallback derriere un flag off" "$([ "$(grep -c 'LOOP_ALLOW_OLLAMA_FALLBACK' loop/loop-overnight.sh)" -ge 2 ] && echo oui)" "oui"
eq "v649: refus MLX inadoptable (pas d'ollama muet)" "$(grep -c 'REFUSE: profil loop MLX inadoptable' loop/loop-overnight.sh)" "1"
eq "v649: preflight local via hermes (chemin reel)" "$(grep -c 'le maker local passe par HERMES' loop/loop-overnight.sh)" "1"

# v6.49.1 (rapport pilote, run all-Opus pendant un incident API Anthropic: BEAUCOUP de
# Telegram muet x3): une panne fournisseur pause au lieu de treadmill, alertes 1x/heure.
eq "v6491: muet API -> quota_pause"        "$(grep -c 'muet = PANNE FOURNISSEUR' loop/loop-overnight.sh)" "1"
eq "v6491: detection via maker_ping"       "$(grep -c "temporarily unavailable|try again at' && ! maker_ping" loop/loop-overnight.sh)" "1"
eq "v6491: telegram muet x3 dedoublonne"   "$(grep -c 'mute_last_notify' loop/loop-overnight.sh)" "2"
eq "v6491: telegram quota dedoublonne"     "$([ "$(grep -c 'quota_last_notify' loop/loop-overnight.sh)" -ge 2 ] && echo oui)" "oui"
eq "v6491: fenetre anti-spam = 1h"         "$([ "$(grep -c 'mute_last_notify:-0} )) -gt 3600' loop/loop-overnight.sh)" -ge 1 ] && [ "$(grep -c 'quota_last_notify:-0} )) -gt 3600' loop/loop-overnight.sh)" -ge 1 ] && echo oui)" "oui"

# v6.49.2 (OOM du run 022707: driver tue en cycle 1, wired 41Go/48 = KV cache 4-parallel x
# 65536). TOUT lms load pin --parallel 1 (un seul maker a la fois, KV /4).
eq "v6492: aucun lms load sans --parallel 1 (driver)" "$(grep -E '^[^#]*lms load' loop/loop-overnight.sh | grep -c 'lms load')" "$(grep -E '^[^#]*lms load' loop/loop-overnight.sh | grep -c 'parallel 1')"
eq "v6492: keeper aussi en parallel 1"     "$(grep -E '^[^#]*lms load' loop/mlx-keeper.sh | grep -c 'parallel 1')" "$(grep -Ec '^[^#]*lms load' loop/mlx-keeper.sh)"

# v6.49.3 (spirale OOM du 09/07: driver OOM-tue en SIGKILL -> run-cycle enfant orphelin
# survit -> resurrecteur relance -> builds concurrents -> OOM -> spirale, 8 drivers).
# Reaper d'orphelins au demarrage: invariant UN cycle par worktree.
eq "v6493: reaper d'orphelins au demarrage" "$(grep -c 'reaper: run-cycle orphelin' loop/loop-overnight.sh)" "1"
eq "v6493: reaper scope par cwd (ce projet seul)" "$(grep -c 'lsof -a -p "$_rc" -d cwd' loop/loop-overnight.sh)" "1"
eq "v6493: reaper avant ecriture RUNNING"  "$([ "$(grep -n 'reaper: run-cycle orphelin' loop/loop-overnight.sh | cut -d: -f1)" -lt "$(grep -n 'echo \$\$ > "\$MAIN/loop/RUNNING"' loop/loop-overnight.sh | cut -d: -f1)" ] && echo oui)" "oui"

# v6.49.4 (VRAIE cause OOM: prompt ~4k tokens => KV petit; 42Go wired = DEUX copies du
# modele. lms load duplique en ':2', LM Studio JIT-autocharge; l'ancien keeper unload-1
# puis load re-dupliquait). Invariant: exactement UNE instance MLX.
eq "v6494: keeper compte les instances"    "$(grep -c 'N="$(lms ps 2>/dev/null | grep -c "$MODEL")"' loop/mlx-keeper.sh)" "1"
eq "v6494: keeper declenche si != 1"       "$(grep -c 'N:-0}" -ne 1 \]' loop/mlx-keeper.sh)" "1"
eq "v6494: keeper unload --all avant load" "$(sed -n '/N:-0}" -ne 1/,/re-pin UNE/p' loop/mlx-keeper.sh | grep -c 'lms unload --all')" "1"
eq "v6494: aucun 'lms unload \"\$MLXM\"' résiduel (driver)" "$(grep -c 'lms unload "$MLXM"' loop/loop-overnight.sh)" "0"
eq "v6494: aucun 'lms unload \"\$MODEL\"' résiduel (keeper)" "$(grep -c 'lms unload "$MODEL"' loop/mlx-keeper.sh)" "0"

# ===== v6.50 (package pilote: critic node + 3 law fixes + taste-skill + routing) =====
# routing par role (benchmark 16 cellules), rien en dur, defauts = comportement historique
eq "v650: maker model routing (codex -m)"  "$(grep -c 'LOOP_MAKER_MODEL:+-m' loop/run-cycle.sh)" "1"
eq "v650: maker effort routing"            "$(grep -c 'LOOP_MAKER_EFFORT:+-c model_reasoning_effort' loop/run-cycle.sh)" "1"
eq "v650: carto model routing (2 familles)" "$([ "$(grep -c 'LOOP_CARTO_MODEL:+' loop/loop-overnight.sh)" -ge 2 ] && echo oui)" "oui"
eq "v650: critic model configurable"       "$(grep -c 'LOOP_CRITIC_MODEL:-' loop/critic.sh)" "1"
# fix #2: gate exige un diff produit (hors loop/) pour GREEN
eq "v650: gate false-green (diff hors loop/)" "$(grep -c 'FALSE-GREEN bloque' loop/loop-overnight.sh)" "2"
eq "v650: exemption carte doc"             "$(grep -c '_SCOPE_CARD" != "doc"' loop/loop-overnight.sh)" "1"
# 0-finding FAIL -> re-revue puis PASS, pas de fix-lot vide
eq "v650: 0-finding FAIL garde"            "$(grep -c 'FAIL a 0 finding' loop/run-cycle.sh)" "1"
# queue-carry: drop des cartes deja mergees
eq "v650: carry-drop deja merge"           "$(grep -c 'carry-drop' loop/loop-overnight.sh)" "1"
# carto-lenses committe (ne salit plus l'arbre MAIN)
eq "v650: carto-lenses committe"           "$(grep -c 'adopt learned carto lenses' loop/loop-overnight.sh)" "1"
# loop-init untrack les organes runtime deja suivis
eq "v650: loop-init untrack runtime"       "$(grep -c 'rm -r --cached --quiet --ignore-unmatch' loop/loop-init.sh)" "1"
# DTO contract: injection mecanique + regle constitution
eq "v650: injection contrat back (front)"  "$(grep -c 'REAL BACKEND CONTRACT' loop/run-cycle.sh)" "1"
eq "v650: API_CTX dans le prompt"          "$(grep -c '\$MODIFY_CTX\$API_CTX\$PREV_WIP' loop/run-cycle.sh)" "1"
eq "v650: regle DTO en constitution"       "$(grep -c 'MATCH THE REAL BACKEND CONTRACT' loop/constitution.md)" "1"
# DAG API-avant-front
eq "v650: regle ordre API-avant-front"     "$(grep -c 'ORDRE API-AVANT-FRONT' loop/loop-overnight.sh)" "1"
# critic node
eq "v650: critic.sh existe"                "$([ -f loop/critic.sh ] && echo oui)" "oui"
eq "v650: critic skip-gracieux"            "$([ "$(grep -c 'skip()' loop/critic.sh)" -ge 1 ] && echo oui)" "oui"
eq "v650: critic vision requise"           "$(grep -c 'vision REQUIRED\|capacite vision' loop/critic.sh)" "2"
eq "v650: critic scope-gele"               "$(grep -c 'SCOPE GELE' loop/critic.sh)" "1"
eq "v650: critic budget cap"               "$([ "$(grep -c 'LOOP_CRITIC_MAX' loop/critic.sh)" -ge 1 ] && echo oui)" "oui"
eq "v650: critic cable a la fermeture"     "$(grep -c 'bash loop/critic.sh' loop/loop-overnight.sh)" "1"
eq "v650: critic seme par loop-init"       "$(grep -c 'critic.sh' loop/loop-init.sh)" "1"
# taste-skill front-tier
eq "v650: taste-skill front existe"        "$([ -f loop/skills-front/design-taste.md ] && echo oui)" "oui"
eq "v650: taste injecte si scope front"    "$([ "$(grep -c 'skills-front/\*.md' loop/run-cycle.sh)" -ge 1 ] && echo oui)" "oui"
eq "v650: taste front-only (scope garde)"  "$(grep -c 'VERIFY_SCOPE:-full}" = "front" \] && ls "\$ROOT"/loop/skills-front' loop/run-cycle.sh)" "1"
eq "v650: design system reste autoritaire" "$(grep -c 'DESIGN-stitch.md.*autoritaire\|project design system is authoritative' loop/skills-front/design-taste.md)" "1"

# v6.50.1 (correction proprietaire du pilote 895c85a: maquette = DIRECTION, pas contrat
# structurel; hierarchie FOND/IDENTITE/DIRECTION; + registre stable des cas d'usage)
eq "v6501: maquette-direction au carto (contractuel)" "$(grep -c 'MAQ_AUTHORITY:-direction' loop/loop-overnight.sh)" "1"
eq "v6501: critic juge par hierarchie"     "$(grep -c 'FOND (non negociable)' loop/critic.sh)" "1"
eq "v6501: critic n'exige jamais coller-maquette" "$(grep -c "coller a la maquette" loop/critic.sh)" "1"
eq "v6501: taste-skill maquette=direction" "$(grep -c 'not a structural contract' loop/skills-front/design-taste.md)" "1"
eq "v6501: registre stable au carto"       "$(grep -c 'REGISTRE STABLE DES CAS' loop/loop-overnight.sh)" "1"
eq "v6501: registre initialise mecaniquement" "$(grep -c 'registre use-cases initialise' loop/loop-overnight.sh)" "1"
eq "v6501: registre append-only"           "$([ "$(grep -c 'append-only' loop/loop-overnight.sh)" -ge 2 ] && echo oui)" "oui"

# v6.50.1 (run premium 10/07: hook SessionEnd des plugins UTILISATEUR pendu 10min apres
# le Done du maker; rc=143; 26min de travail Opus vert REVERTE): sessions maker isolees.
eq "v6501: maker claude isole des plugins user" "$(grep -Ec '^[^#]*--setting-sources=project' loop/run-cycle.sh)" "1"
eq "v6503: maker claude sans MCP (strict)"    "$(grep -Ec '^[^#]*--strict-mcp-config' loop/run-cycle.sh)" "1"

# v6.50.2 (rapport pilote run 5 sur v6.50: 4 bugs). Lignee worktree, prereqs critic.
eq "v6502: resume fusionne dev dans le run"  "$(grep -c 'resume: dev fusionne' loop/loop-overnight.sh)" "2"
eq "v6502: resolution loi<-dev produit<-run" "$(grep -c "checkout --theirs -- loop/constitution" loop/loop-overnight.sh)" "1"
eq "v6502: critic local par ligne (bash 3.2)" "$(grep -c 'local r="$1"; local lab="$2"; local size="$3"' loop/critic.sh)" "1"
eq "v6502: critic fallback npx -y playwright" "$(grep -c 'npx -y playwright' loop/critic.sh)" "1"
eq "v6502: critic scan gere guillemets doubles" "$(grep -c "sed -E .s/path:" loop/critic.sh)" "1"
eq "v6502: routes a parametre gardees (sample)" "$([ "$(grep -c 'EYE_ROUTE_SAMPLE' loop/critic.sh)" -ge 1 ] && echo oui)" "oui"
eq "v6502: EYE_ROUTES contractuel au pack"   "$(grep -c '^EYE_ROUTES=' loop/stack.d/angular-spring.sh)" "1"

# v6.50.4 (pilote: REPORT unbound au semis sur front vide; faux-vide EYE_PAGES_DIR).
# Garde statique: l'assignation de REPORT precede son PREMIER usage hors fonction/commentaire.
eq "v6504: REPORT assigne avant 1er usage" "$([ "$(grep -n 'RUN="$(date +%Y%m%d-%H%M%S)"; REPORT=' loop/loop-overnight.sh | head -1 | cut -d: -f1)" -lt "$(grep -n 'SCAF' loop/loop-overnight.sh | head -1 | cut -d: -f1)" ] && echo oui)" "oui"
eq "v6504: assignation tardive defensive" "$(grep -c ': "${REPORT:=loop/reports' loop/loop-overnight.sh)" "1"
eq "v6504: pack EYE_PAGES_DIR standalone"  "$(grep -c '^EYE_PAGES_DIR=' loop/stack.d/angular-spring.sh)" "1"

# v6.50.5 (nuit 10/07: internet perdu ~02:00, 6 cycles ConnectionRefused a 12min chacun,
# trop lents pour la sentinelle <60s): l internet se traverse comme la nuit.
eq "v6505: sentinelle internet-perdu"     "$(grep -c 'INTERNET PERDU (signature reseau' loop/loop-overnight.sh)" "1"
eq "v6505: pause bornee par la deadline"  "$(sed -n '/INTERNET PERDU/,/FF_N=0; continue/p' loop/loop-overnight.sh | grep -c 'deadline')" "1"
eq "v6505: carte preservee (continue)"    "$(sed -n '/INTERNET PERDU/,/FF_N=0; continue/p' loop/loop-overnight.sh | grep -c 'FF_N=0; continue')" "1"
eq "v6505: telegram apres reconnexion"    "$(sed -n '/INTERNET REVENU/,/notify_phone/p' loop/loop-overnight.sh | grep -c 'notify_phone')" "1"
eq "v6505: signatures reseau en autopsie" "$([ "$(grep -c 'ConnectionRefused' loop/loop-overnight.sh)" -ge 3 ] && echo oui)" "oui"

# v6.50.6 (run 1h premium: les 3 rouges etaient des FAUX NEGATIFS de formatage; probes
# backtickees = substitution bash = echec garanti; une analyse de 18min detruite).
eq "v6506: backticks strip centralise (runnable_probes)" "$(sed -n '/^runnable_probes(){/,/^}/p' loop/loop-overnight.sh | grep -c 'p="${p#\\`}"')" "1"
eq "v6506: bank avant revert sur probe-fail" "$(sed -n '/PROBE FAILED (${DUR}m)/,/route_failure/p' loop/loop-overnight.sh | grep -c 'bank_wip')" "1"

# v6.50.7 (les cartes naissent d ORGANES: assainisseur unique a la naissance).
eq "v6507: sanitize_cards defini"          "$(grep -c '^sanitize_cards(){' loop/loop-overnight.sh)" "1"
eq "v6507: appele aux 3 atterrissages"     "$(grep -cE '^ *sanitize_cards$' loop/loop-overnight.sh)" "3"
eq "v6507: consigne raw au distiller"      "$(grep -c 'NEVER wrap them in markdown backticks' loop/distill.sh)" "1"

# v6.51 CLIENT MYSTERE (retour proprietaire du pilote: le loop plafonne a son juge le
# plus exigeant; le critic vitrine ne sent pas un tableau sans tri; couvert = endpoint).
eq "v651: 6 lentilles planchers UX"        "$(grep -c '^- PLANCHER-\|^- PARCOURS-EXPERIENCE' loop/carto-lenses.md)" "6"
eq "v651: critic = client mystere"         "$(grep -c 'CLIENT MYSTERE, PAS UN CRITIQUE DE VITRINE' loop/critic.sh)" "1"
eq "v651: planchers opposables au critic"  "$(grep -c 'PLANCHERS UX OPPOSABLES' loop/critic.sh)" "1"
eq "v651: critic seme les cartes parcours" "$(grep -c "carte 'parcours-<uc>' VALUE P1" loop/critic.sh)" "1"
eq "v651: references externes (gov.uk)"    "$(grep -c 'gov.uk' loop/critic.sh)" "1"
eq "v651: COUVERT-VERT exige le parcours"  "$(grep -c 'REDEFINITION DE COUVERT' loop/loop-overnight.sh)" "1"
eq "v651: la couverture peut baisser"      "$(grep -c 'BAISSER quand la barre monte' loop/loop-overnight.sh)" "1"

# v6.51.1 (pilote: ZERO upload dans un systeme de depot de pieces; il manquait le
# COMMON SENSE): test de l evidence de categorie, avant toute esthetique.
eq "v6511: lentille evidence de categorie" "$(grep -c '^- EVIDENCE-DE-CATEGORIE' loop/carto-lenses.md)" "1"
eq "v6511: critic ordre des passes"        "$(grep -c 'ORDRE DES PASSES' loop/critic.sh)" "1"
eq "v6511: evidence avant esthetique"      "$(grep -c 'AVANT tout le reste' loop/critic.sh)" "1"
eq "v6511b: evidence langues officielles"  "$(grep -c 'langues officielles du pays cible' loop/carto-lenses.md)" "1"

# v6.51.3 (pilote: 4 cartes FINIES jetees en PROBEFAIL x2 + PARK parce que le PROBE
# executait playwright: EPERM dans le sandbox maker, timeout cote driver. Doctrine: une
# PROBE verifie l existence+contenu du spec; l EXECUTION appartient a la phase e2e).
eq "v6513: probes playwright sautees inline x4 (v681: +garde reparation)" "$(grep -c 'playwright test\"\*) continue' loop/loop-overnight.sh)" "4"
eq "v6513: regle ecrans interdit l'execution e2e en PROBE" "$(grep -c 'INTERDIT en PROBE' loop/loop-overnight.sh)" "1"
eq "v6513: lentille RUNTIME corrigee"       "$(grep -c 'JAMAIS npx playwright test en PROBE' loop/carto-lenses.md)" "1"
eq "v6513: critic parcours = existence du spec" "$(grep -c 'JAMAIS son execution, reservee au harnais' loop/critic.sh)" "1"

# v6.52 (design proprietaire du pilote: run de nuit autonome et econome). Quota-gate
# proactif, triage mecanique de la revue de lot, passe front-review, lint playwright.
eq "v652: quota_gate defini"               "$(grep -c '^quota_gate(){' loop/loop-overnight.sh)" "1"
eq "v652: gate appele avant chaque cycle"  "$(grep -c 'quota_gate   # v6.52' loop/loop-overnight.sh)" "1"
eq "v652: cout appris (EMA), pas de constante" "$([ "$(sed -n '/^quota_gate(){/,/^}/p' loop/loop-overnight.sh | grep -c 'ema')" -ge 5 ] && echo oui)" "oui"
eq "v652: capteur muet ne bloque jamais"   "$(sed -n '/^quota_gate(){/,/^}/p' loop/loop-overnight.sh | grep -c 'capteur muet')" "1"
eq "v652: reserve de fermeture claude"     "$(sed -n '/^quota_gate(){/,/^}/p' loop/loop-overnight.sh | grep -c '92')" "2"
eq "v652: triage lot bon-marche = gate seul" "$(grep -c 'TRIAGE: lot .$LOTID. BON-MARCHE' loop/loop-overnight.sh)" "1"
eq "v652: triage conservateur (contrat => chair)" "$(grep -c '_CONTRACT=1' loop/loop-overnight.sh)" "1"
eq "v652: triage debrayable"               "$(grep -c 'LOOP_TRIAGE:-1' loop/loop-overnight.sh)" "1"
eq "v652: front-review a la fermeture"     "$(grep -c 'FRONT-REVIEWER du loop' loop/loop-overnight.sh)" "1"
eq "v652: front-review modele configurable" "$([ "$(grep -c 'LOOP_FRONT_REVIEW_MODEL' loop/loop-overnight.sh)" -ge 1 ] && echo oui)" "oui"
eq "v652: front-review emet des cartes 61-*" "$([ "$(grep -c 'loop/tasks/61-' loop/loop-overnight.sh)" -ge 2 ] && echo oui)" "oui"
eq "v652: lint jambe playwright en probe"  "$(grep -c 'jambe playwright en PROBE' loop/loop-overnight.sh)" "1"

# v6.53 (diagnostic 11/07: hermes memory add/store n'existe pas en v0.18; memoire built-in
# = fichier memories/MEMORY.md toujours active; pont maker premium -> memoire hermes).
eq "v653: seed ecrit dans MEMORY.md"       "$(grep -c 'MEMF="$MEMDIR/MEMORY.md"' loop/setup-hermes-profile.sh)" "1"
eq "v653: plus d appel hermes memory casse" "$(grep -c 'timeout 30 hermes memory' loop/setup-hermes-profile.sh)" "0"
eq "v653: pont memory_bridge defini"       "$(grep -c '^memory_bridge(){' loop/loop-overnight.sh)" "1"
eq "v653: pont appele a la fermeture"      "$(grep -cE '^memory_bridge 2>/dev/null' loop/loop-overnight.sh)" "1"
eq "v653: pont verse les verts du run"     "$(sed -n '/^memory_bridge(){/,/^}/p' loop/loop-overnight.sh | grep -c 'GREEN')" "1"

# v6.54 (defaut 12/07: 6 cartes de defaut proprietaire battues par le polissage P1 du
# critique car sans VALUE): un retour humain naît prioritaire (URGENT=P0, sinon P1).
eq "v654: carte feedback VALUE par defaut"  "$(sed -n '/===CARD 40-/,/===END===/p' loop/loop-overnight.sh | grep -c 'VALUE: P1')" "1"
eq "v654: URGENT feedback = P0"             "$(grep -c 'mets VALUE: P0' loop/loop-overnight.sh)" "1"

# v6.55 (defaut 12/07: cartes feedback a PROBE en prose => faux rouge => fix reverte).
eq "v655: prompt exige commande shell"     "$(grep -c 'UNE COMMANDE SHELL EXECUTABLE, JAMAIS une phrase' loop/loop-overnight.sh)" "1"
eq "v655: lint attrape le probe prose"     "$(grep -c 'PROBE EN PROSE' loop/loop-overnight.sh)" "1"

# v6.56 (AUTO-REPARATION du construire-et-reverter, defaut 12/07). runnable_probes
# neutralise les probes non-executables (le bon code passe au gate au lieu d'etre reverte);
# garde sterile qui crie et CONTINUE (jamais de pause) si N cycles sans vert.
eq "v656: runnable_probes defini"          "$(grep -c '^runnable_probes(){' loop/loop-overnight.sh)" "1"
eq "v656: probe prose neutralisee"         "$(grep -c 'probe non-executable NEUTRALISEE' loop/loop-overnight.sh)" "1"
eq "v656: 4 sites lisent runnable_probes (v681)"  "$(grep -c 'done < <(runnable_probes "$CARD")' loop/loop-overnight.sh)" "4"
eq "v656: autodone exige un probe executable" "$(grep -c 'if \[ -n "$(runnable_probes "$CARD")" \]' loop/loop-overnight.sh)" "1"
eq "v656: garde sterile crie et continue"  "$(grep -c 'RUN STERILE' loop/loop-overnight.sh)" "3"
eq "v656: sterile ne pause pas (continue)" "$(sed -n '/GARDE STERILE/,/mem_police/p' loop/loop-overnight.sh | grep -c 'sleep')" "0"

# v6.56.1 (rg -E = encoding chez ripgrep, probe rouge a vie): dry-run au semis, rc>=2 = malformee.
eq "v6561: lint dry-run probes (rc>=2)"    "$([ "$(grep -c 'probe MALFORMEE' loop/loop-overnight.sh)" -ge 2 ] && echo oui)" "oui"
eq "v6571: neutralisation rc>=2 a l execution" "$(grep -c 'MALFORMEE NEUTRALISEE' loop/loop-overnight.sh)" "1"
eq "v6561: exemple loi sans rg -qE"        "$(grep -c 'rg -qE ' loop/loop-overnight.sh)" "0"

# v6.57 (2 reboots machine sans trace en 2 jours, 4h de fenetre perdues): resurrecteur au boot.
eq "v657: driver ecrit NIGHT-PLAN"         "$(grep -c 'echo "$deadline" > "$MAIN/loop/NIGHT-PLAN"' loop/loop-overnight.sh)" "1"
eq "v657: NIGHT-ENV porte le routing role" "$(grep -c 'LOOP_CARTO_MODEL=%s LOOP_CRITIC_MODEL=%s' loop/loop-overnight.sh)" "1"
eq "v657: boot-resurrect existe+executable" "$([ -x loop/boot-resurrect.sh ] && echo oui)" "oui"
eq "v657: jamais un run neuf (doctrine)"   "$(grep -c 'ne demarre JAMAIS un run neuf' loop/boot-resurrect.sh)" "1"
eq "v657: reliquat en heure absolue"       "$(grep -c 'HHMM="$(date -r "$DL"' loop/boot-resurrect.sh)" "1"

# v6.58 (13/07: refus sur worktree orpheline): auto-nettoyage au lieu de refuser.
eq "v658: worktree orpheline auto-nettoyee" "$(grep -c 'worktree orpheline detectee' loop/loop-overnight.sh)" "1"
eq "v658: prune avant rm"                   "$([ "$(grep -n 'git worktree prune' loop/loop-overnight.sh | head -1 | cut -d: -f1)" -lt "$(grep -n 'worktree orpheline detectee' loop/loop-overnight.sh | cut -d: -f1)" ] && echo oui)" "oui"

# v6.59 (3 reboots machine sans trace 11/12/13-07, chacun a ~1-2 min d'un chromium
# headless: crash renderer GPU Metal -> reset dur sans panic). GPU coupe + reap garanti.
# config playwright: chemin porte par le contrat, assertion conditionnee a son existence
_PWCFG="$( . loop/stack.sh 2>/dev/null; printf '%s' "${FRONT_DIR:-frontend}" )/playwright.config.ts"
if [ -f "$_PWCFG" ]; then
  eq "v659: config playwright GPU off"      "$(grep -c 'use-gl=swiftshader' "$_PWCFG")" "1"
  eq "v659: config garde headless"          "$(grep -c 'headless: true' "$_PWCFG")" "1"
fi
eq "v659: reap_browsers defini"             "$(grep -c 'reap_browsers()' loop/loop-overnight.sh)" "1"
eq "v659: assert_pw_gpu_off defini"         "$(grep -c 'assert_pw_gpu_off()' loop/loop-overnight.sh)" "1"
eq "v659: reap appele EN TETE de boucle"    "$([ "$(grep -n '^  reap_browsers' loop/loop-overnight.sh | head -1 | cut -d: -f1)" -gt "$(grep -n '^while :; do' loop/loop-overnight.sh | tail -1 | cut -d: -f1)" ] && echo oui)" "oui"
eq "v659: reassertion GPU appelee"          "$(grep -c '^  assert_pw_gpu_off' loop/loop-overnight.sh)" "1"
eq "v659: e2e reap chromium au cleanup"     "$(grep -cE 'pkill -f .headless_shell' loop/e2e.sh)" "1"
eq "v659: critic reap apres screenshots"    "$(grep -cE 'pkill -f .headless_shell' loop/critic.sh)" "1"

# v6.60 (confinement total: le CLI `playwright screenshot` du critic ne lisait pas la
# config -> dernier chromium GPU-ON du loop; + passe d'interaction scroll de la revue 13/07).
eq "v660: critic-shot.mjs existe"           "$([ -f loop/critic-shot.mjs ] && echo oui)" "oui"
eq "v660: script GPU-off explicite"         "$(grep -c 'use-gl=swiftshader' loop/critic-shot.mjs)" "1"
eq "v660: passe scroll bas puis haut"       "$(grep -c 'scrollTo(0, document.body.scrollHeight)' loop/critic-shot.mjs)" "1"
eq "v660: critic prefere le script confine" "$(grep -c 'critic-shot.mjs' loop/critic.sh)" "2"
eq "v660: fallback CLI conserve"            "$(grep -c 'playwright screenshot' loop/critic.sh 2>/dev/null | head -1)" "1"

# v6.61 (3 RED consecutifs 42-auth-jwt-back: la carte exige 401, le smoke attendait 200 nu
# -> conflit loi-contre-feature, la carte ne pouvait jamais verdir). Smoke auth-aware.
eq "v661: smoke auth-aware present"         "$([ "$(grep -c 'SMOKE_TOKEN_CMD' loop/verify.sh)" -ge 3 ] && echo oui)" "oui"
eq "v661: retente avec Bearer"              "$(grep -c 'Authorization: Bearer .TOK' loop/verify.sh)" "1"
eq "v661: sans jeton = echec explicite"     "$(grep -c "SMOKE_TOKEN_CMD n'a rendu aucun jeton" loop/verify.sh)" "1"
eq "v661: stack fournit SMOKE_TOKEN_CMD"    "$(grep -c '^SMOKE_TOKEN_CMD=' loop/stack.sh)" "1"
eq "v661: boots avec profil dev-auth"       "$(grep -c 'spring-boot.run.profiles=dev-auth' loop/stack.sh)" "2"
# v6.84: assertion conditionnee a l'existence de la carte (fuite relevee par le portage RH:
# le harnais PARTAGE greppait une carte du projet d'origine, 1 FAIL garanti ailleurs).
if [ -f loop/tasks/42-auth-jwt-back.md ]; then
  eq "v661: carte pinne les usernames"      "$(grep -c 'ca, respcaf, assistante' loop/tasks/42-auth-jwt-back.md)" "1"
fi

eq "v6601: critic-shot resolu via WT (pas ROOT)" "$(grep -c 'SHOT_MJS="\$WT/loop/critic-shot.mjs"' loop/critic.sh)" "1"

eq "v6602: thermal-ledger existe+executable" "$([ -x loop/thermal-ledger.sh ] && echo oui)" "oui"
eq "v6602: ledger hors worktree (persiste)"   "$(grep -c 'THERMAL_LEDGER.*HOME' loop/thermal-ledger.sh)" "1"

# v6.62 (sidecar: 2e repo dans le perimetre du loop, commit/reset couple).
eq "v662: sidecar declare dans stack"       "$(grep -c '^SIDECAR_DIR=' loop/stack.sh)" "1"
eq "v662: sidecar_reset defini"             "$(grep -c 'sidecar_reset()' loop/loop-overnight.sh)" "1"
eq "v662: sidecar_reset en tete de boucle"  "$(grep -c '^  sidecar_reset' loop/loop-overnight.sh)" "1"
eq "v662: sidecar_commit couple au GREEN"   "$(grep -c 'sidecar_commit ' loop/loop-overnight.sh)" "1"
eq "v662: garde dure (jamais reset le repo principal)" "$(grep -c 'jamais reset le repo principal' loop/loop-overnight.sh)" "1"
eq "v662: gate sidecar dans verify"         "$(grep -c 'SIDECAR TESTS FAILED' loop/verify.sh)" "1"
eq "v662: maker autorise le sidecar"        "$(grep -c 'SCOPE: sidecar' loop/run-cycle.sh)" "1"

# v6.62.1 (1er run multi-repo: carte sidecar-only = "no change" cote principal, travail JETE au reset).
eq "v6621: sidecar_dirty defini"            "$(grep -c 'sidecar_dirty()' loop/loop-overnight.sh)" "1"
eq "v6621: no-change inclut le sidecar"     "$(grep -c 'sidecar sale = vrai changement' loop/loop-overnight.sh)" "1"
eq "v6621: FALSE-GREEN exempte sidecar"     "$([ "$(grep -c '!= "sidecar"' loop/loop-overnight.sh)" -ge 1 ] && echo oui)" "oui"
eq "v6621: commit principal vide tolere (marqueur)" "$([ "$(grep -c 'allow-empty' loop/loop-overnight.sh)" -ge 1 ] && echo oui)" "oui"

eq "v663: pont lecons puise hints.d"        "$([ "$(grep -c 'loop/hints.d/' loop/loop-overnight.sh)" -ge 1 ] && echo oui)" "oui"
eq "v663: boucle glob lesson-*.md morte supprimee" "$(grep -c 'for lz in loop/proposals' loop/loop-overnight.sh)" "0"

# v6.64 (churn decision-*: cartes faites, probes bruts passants mais neutralises => rejeu infini).
eq "v664: raw_probes_all_pass defini"       "$(grep -c 'raw_probes_all_pass()' loop/loop-overnight.sh)" "1"
eq "v664: AUTODONE-LATE dans le no-change"  "$([ "$(grep -c 'AUTODONE-LATE' loop/loop-overnight.sh)" -ge 3 ] && echo oui)" "oui"

eq "v665: telegram prefixe projet (notify)"  "$(grep -c 'text=..tag. .1' loop/loop-overnight.sh)" "1"
eq "v665: digest prefixe projet"             "$(grep -c 'LOOP_PROJECT_TAG' loop/morning-digest.sh)" "1"
eq "v665: resurrecteur prefixe projet"       "$(grep -c 'basename ..MAIN... 🔁' loop/resurrect.sh)" "1"

# v6.66 (rapport pilote 16/07: no-change d'une carte deja faite lu comme panne infra,
# model_alive sonde la mauvaise couche pour un maker frontier -> HEAL 7h a vide).
eq "v666: carte testee AVANT infra (NOOP hors model_alive)" "$([ "$(grep -n 'NOOP-DONE:' loop/loop-overnight.sh | head -1 | cut -d: -f1)" -lt "$(grep -n 'if \[ ..DUR. -lt 2 \]' loop/loop-overnight.sh | head -1 | cut -d: -f1)" ] && echo oui)" "oui"
eq "v666: AUTODONE-LATE avant la garde infra" "$([ "$(grep -n 'AUTODONE-LATE:' loop/loop-overnight.sh | head -1 | cut -d: -f1)" -lt "$(grep -n 'if \[ ..DUR. -lt 2 \]' loop/loop-overnight.sh | head -1 | cut -d: -f1)" ] && echo oui)" "oui"
eq "v666: maker frontier verbeux = vivant, pas infra" "$(grep -c 'maker frontier VERBEUX' loop/loop-overnight.sh)" "1"
eq "v666: exit verbeux lu du cycle log" "$(grep -c '_MAKER_VERBOSE' loop/loop-overnight.sh)" "3"

eq "v667: queue complete purge NIGHT-PLAN" "$(grep 'queue complete.*rm -f.*NIGHT-PLAN' loop/loop-overnight.sh | wc -l | tr -d ' ')" "1"
eq "v667: resurrect log horodate"          "$(grep -c 'loop-resurrected-..date' loop/resurrect.sh)" "1"

# v6.68 (java/node orphelins post-run: le reaper ne connaissait que chromium+ng).
eq "v668: reap_worktree_orphans defini"    "$(grep -c 'reap_worktree_orphans()' loop/loop-overnight.sh)" "1"
eq "v668: appele en tete de cycle"         "$(grep -c '^  reap_worktree_orphans' loop/loop-overnight.sh)" "1"
eq "v668: appele au cleanup (garde type)"  "$(grep -c 'type reap_worktree_orphans' loop/loop-overnight.sh)" "1"
eq "v668: organes du run exemptes"         "$(grep -c 'loop-overnight.*run-cycle.*claude.*codex.*hermes' loop/loop-overnight.sh)" "1"

eq "v669: captures critique sous /tmp reel (juge vision peut lire)" "$(grep -c 'mktemp -d "/tmp/critic-shots' loop/critic.sh)" "1"

# v6.70 (rapport pilote 16/07: le critic seme des cartes 60-* avec probes rg-OU que
# le probe-lint du meme harnais refuse au run suivant => AUTODONE menteur possible).
eq "v670: split_or_probes defini"          "$(grep -c 'split_or_probes()' loop/critic.sh)" "1"
eq "v670: applique a la fermeture de carte" "$(grep -c 'split_or_probes ..CARDF.' loop/critic.sh)" "1"
eq "v670: prompt interdit alternance |"     "$(grep -c "JAMAIS d'alternance" loop/critic.sh)" "1"
T670="$(mktemp -d /tmp/t670-XXXXXX)"
sed -n '/^split_or_probes()/,/^}/p' loop/critic.sh > "$T670/fn.sh"
printf '%s\n' 'PROBE: rg -q "aa|bb" src' 'PROBE: rg -q "(cc|dd)" src' > "$T670/c.md"
bash -c ". '$T670/fn.sh'; split_or_probes '$T670/c.md'"
eq "v670: OU simple scinde en 2 PROBE ET"  "$(grep -c '^PROBE: rg -q ' "$T670/c.md")" "3"
eq "v670: token aa isole"                  "$(grep -c 'rg -q "aa" src' "$T670/c.md")" "1"
eq "v670: groupe regex laisse intact"      "$(grep -c '(cc|dd)' "$T670/c.md")" "1"
rm -rf "$T670"

# v6.71 (pilote 17/07: WARN probe-lint sans effet, AUTODONE menteur 40 min apres sur
# un `rg A || rg B` dont le 2e membre etait vrai avant la feature. Le lint doit APPLIQUER).
eq "v671: card_has_or_probes defini"        "$(grep -c 'card_has_or_probes()' loop/loop-overnight.sh)" "1"
eq "v671: AUTODONE au pick garde"           "$(grep -c '! card_has_or_probes ..CARD.' loop/loop-overnight.sh)" "2"
eq "v671: AUTODONE-LATE garde aussi"        "$(grep -c 'card_has_or_probes.*raw_probes_all_pass' loop/loop-overnight.sh)" "1"
eq "v671: lint annonce AUTODONE INTERDIT"   "$(grep -c 'AUTODONE INTERDIT' loop/loop-overnight.sh)" "1"
T671="$(mktemp -d /tmp/t671-XXXXXX)"
sed -n '/^card_has_or_probes()/,/^}/p' loop/loop-overnight.sh > "$T671/fn.sh"
printf '%s\n' 'PROBE: rg -q "aa|bb" src' > "$T671/or-pattern.md"
printf '%s\n' 'PROBE: rg -q "aa" f || rg -q "bb" f' > "$T671/or-shell.md"
printf '%s\n' 'PROBE: rg -q "aa" src' 'PROBE: rg -q "bb" src' > "$T671/et.md"
eq "v671: alternance pattern detectee"  "$(bash -c ". '$T671/fn.sh'; card_has_or_probes '$T671/or-pattern.md' && echo oui" 2>/dev/null)" "oui"
eq "v671: OU shell detecte"             "$(bash -c ". '$T671/fn.sh'; card_has_or_probes '$T671/or-shell.md' && echo oui" 2>/dev/null)" "oui"
eq "v671: probes ET sains non flagues"  "$(bash -c ". '$T671/fn.sh'; card_has_or_probes '$T671/et.md' || echo non" 2>/dev/null)" "non"
rm -rf "$T671"

# v6.72 (matin 17/07: 9 fix-lots sans VALUE jamais pioches derriere les P0, e2e reste rouge).
eq "v672: fix-lot nait P0"                 "$(sed -n '/Fix lot .LOTID, reviewer findings/,/} > ..FIX./p' loop/loop-overnight.sh | grep -c 'VALUE: P0')" "1"
eq "v672: front-review emet P0"            "$(grep -c 'VALUE: P0 obligatoire' loop/loop-overnight.sh)" "1"

# v6.73 (faille pilote 17/07: dep ajoutee au manifeste, lock jamais regenere, install du
# preflight suivant meurt "not in sync", driver mort avant cycle 1). Fix PORTABLE via contrat.
eq "v673: resync du lock via contrat"        "$(grep -c 'bash -c ..STACK_LOCK_SYNC_CMD' loop/loop-overnight.sh)" "1"
eq "v673: contrat porte lock-sync"           "$(grep -c 'STACK_LOCK_SYNC_CMD=' loop/stack.sh)" "1"
eq "v673: contrat porte le manifeste"        "$(grep -c 'STACK_LOCK_MANIFEST=' loop/stack.sh)" "1"
eq "v673: resync conditionne au manifeste au diff" "$(grep -c 'git status --porcelain -- ..STACK_LOCK_MANIFEST' loop/loop-overnight.sh)" "1"
eq "v673: install sans --silent (trace erreur)" "$(grep -c 'npm ci --silent' loop/stack.sh)" "0"

# v6.74 (faille pilote 17/07: octet non-UTF-8 d'un log d'outil colle en CONTEXT fait
# HARD-FAIL codex exec "invalid UTF-8 in arguments", carte re-echoue chaque run).
eq "v674: prompt maker assaini avant codex"  "$(grep -c 'iconv -f UTF-8 -t UTF-8 -c' loop/run-cycle.sh)" "2"
eq "v674: front-review prompt assaini"       "$(grep -c 'iconv -f UTF-8 -t UTF-8 -c' loop/loop-overnight.sh)" "1"
# preuve fonctionnelle: un prompt avec octet 0xFF ressort en UTF-8 valide
T674="$(mktemp -d /tmp/t674-XXXXXX)"; printf 'avant\xffapres' > "$T674/dirty"
iconv -f UTF-8 -t UTF-8 "$T674/dirty" >/dev/null 2>&1 && _pre=propre || _pre=poison
iconv -f UTF-8 -t UTF-8 -c "$T674/dirty" > "$T674/clean" 2>/dev/null
iconv -f UTF-8 -t UTF-8 "$T674/clean" >/dev/null 2>&1 && _post=propre || _post=poison
eq "v674: octet 0xFF est bien un poison"     "$_pre" "poison"
eq "v674: iconv -c rend le contenu propre"   "$_post" "propre"
rm -rf "$T674"

# v6.75 (demande pilote 17/07: captures authentifiees pour le critic, sinon routes
# protegees = page login, juge vision aveugle sur le produit interne). Portable par contrat.
eq "v675: critic-shot accepte un 4e arg session" "$(grep -c 'cle=jeton' loop/critic-shot.mjs)" "4"
eq "v675: session posee avant navigation (addInitScript)" "$(grep -c 'addInitScript' loop/critic-shot.mjs)" "3"
eq "v675: garde anti-faux-ecran (redirection login)" "$(grep -c 'session refusee' loop/critic-shot.mjs)" "1"
eq "v675: critic resout le jeton par contrat" "$(grep -c 'EYE_SESSION_TOKEN_CMD' loop/critic.sh)" "5"
eq "v675: critic passe la session a shoot (v676: par route)" "$(grep -c 'session_arg_for' loop/critic.sh)" "2"
eq "v675: contrat porte cle + commande jeton" "$(grep -c 'EYE_SESSION_KEY=' loop/stack.sh)" "1"
_SKEY="$( . loop/stack.sh 2>/dev/null; printf '%s' "${EYE_SESSION_KEY:-}" )"
eq "v675: loi ne connait pas la cle localStorage" "$(if [ -n "$_SKEY" ]; then grep -cF -- "$_SKEY" loop/critic.sh loop/critic-shot.mjs | grep -c ':0'; else echo 2; fi)" "2"

# v6.76 (pilote: brancher v6.75 chez eux -> 3 extensions loi, toutes retro-compatibles).
eq "v676: mjs accepte le store en 5e arg"    "$(grep -c 'local|session' loop/critic-shot.mjs)" "2"
eq "v676: mjs choisit session|localStorage"  "$(grep -c 'sessionStorage : localStorage' loop/critic-shot.mjs)" "1"
eq "v676: critic mappe route->role"          "$(grep -c 'route_role()' loop/critic.sh)" "1"
eq "v676: critic resout la session par route" "$(grep -c 'session_arg_for()' loop/critic.sh)" "1"
eq "v676: extraction neutre (head -c, plus de strip en code)" "$(grep -v '^[[:space:]]*#' loop/critic.sh | grep -c ':space:')" "0"
eq "v676: extraction cap taille (head -c)" "$(grep -c 'head -c 8192' loop/critic.sh)" "1"
eq "v676: contrat store passe au mjs"        "$(grep -c 'EYE_STORE_ARG' loop/critic.sh)" "2"
# preuve fonctionnelle du dispatch par role SOUS BASH (zsh ne word-split pas)
T676="$(mktemp -d /tmp/t676-XXXXXX)"
sed -n '/^route_role()/,/^}/p' loop/critic.sh > "$T676/rr.sh"
_R="$(bash -c '. '"$T676"'/rr.sh; EYE_ROUTE_ROLES="/a=ALPHA /b=BETA"; route_role /b')"
eq "v676: route_role dispatch correct (bash)" "$_R" "BETA"
_R2="$(bash -c '. '"$T676"'/rr.sh; EYE_ROUTE_ROLES="/a=ALPHA"; route_role /inconnu')"
eq "v676: route hors map = vide (anonyme)"   "$_R2" ""
rm -rf "$T676"

# v6.77 (trou de loi pilote 18/07: e2e.sh sert un build sans verifier sa fraicheur).
eq "v677: garde fraicheur build dans e2e"    "$(grep -c 'E2E_PREBUILD_CMD' loop/e2e.sh)" "2"
eq "v677: test fraicheur via find -newer"    "$(grep -Fc 'find "$E2E_BUILD_SRC" -newer' loop/e2e.sh)" "1"
eq "v677: rebuild si artefact absent"        "$(grep -Fc '! -e "$E2E_BUILD_ARTIFACT"' loop/e2e.sh)" "1"
eq "v677: garde inactive sans contrat" "$(grep -c 'E2E_BUILD_ARTIFACT' loop/stack.sh)" "0"

# v6.78 (nuit pilote 17-18/07 perdue: quota-gate en boucle sur une mesure FIGEE a 83%,
# codex ayant remplace la fenetre 5h par un quota hebdomadaire non rechargeable).
eq "v678: garde non-progression"          "$(grep -c 'mesure FIGEE' loop/loop-overnight.sh)" "1"
eq "v678: compteur de mesures identiques" "$(grep -c '_qg_same' loop/loop-overnight.sh)" "5"
eq "v678: plafond de tranches de pause"   "$(grep -c "_QG_MAX_SLICES" loop/loop-overnight.sh)" "5"
eq "v678: plafond surchargeable"          "$(grep -c 'LOOP_QUOTA_MAX_SLICES' loop/loop-overnight.sh)" "1"
eq "v678: les 2 sorties rendent la main"  "$(sed -n '/v6.78/,/deadline proche/p' loop/loop-overnight.sh | grep -c 'return 0')" "3"

# v6.79 (run 27/07: "API Error: 529 Overloaded" apres 13min => HARD-FAIL, carte accusee a
# tort. Le 529 est une saturation fournisseur transitoire: ni code, ni quota, ni reseau).
eq "v679: garde fournisseur sature"        "$(grep -c 'FOURNISSEUR SATURE' loop/loop-overnight.sh)" "2"
eq "v679: signatures 529/503/overloaded"   "$(grep -c 'overloaded|service unavailable' loop/loop-overnight.sh)" "1"
eq "v679: plafond 3 episodes par run"      "$(grep -c 'OVL_N' loop/loop-overnight.sh)" "4"
eq "v679: carte preservee (continue)"      "$(sed -n '/FOURNISSEUR SATURE/,/^    fi/p' loop/loop-overnight.sh | grep -c 'FF_N=0; continue')" "1"
eq "v679: garde AVANT route_failure"       "$([ "$(grep -n 'FOURNISSEUR SATURE (529' loop/loop-overnight.sh | head -1 | cut -d: -f1)" -lt "$(grep -n 'perf_log HARD' loop/loop-overnight.sh | head -1 | cut -d: -f1)" ] && echo oui)" "oui"

# v6.80 (run 27/07: carte "00-F1-00-F1-45-ged-...-fixes-fixes". Nom recursif => base qui
# derive => compteur neuf => LOOP_LOT_MAXGEN jamais atteint. Et compteur dans le worktree).
eq "v680: base normalisee (strip repete jusqu'au point fixe)"  "$(grep -Fc 's/^00-F[0-9]*-//' loop/loop-overnight.sh)" "1"
eq "v680: nom bati sur LOT_BASE"           "$(grep -Fc '00-F$GEN-$LOT_BASE-fixes.md' loop/loop-overnight.sh)" "1"
eq "v680: compteur persiste hors worktree" "$(grep -Fc 'CF="$MAIN/loop/lot-gen/' loop/loop-overnight.sh)" "1"
_norm(){ b="$1"; while :; do _l="$(printf '%s' "$b" | sed 's/^00-F[0-9]*-//; s/-fixes$//')"; [ "$_l" = "$b" ] && break; b="$_l"; done; printf '%s' "$b"; }
eq "v680: base gen1 normalisee"  "$(_norm '00-F1-45-ged-recherche-client-fixes')" "45-ged-recherche-client"
eq "v680: base gen2 recursive normalisee" "$(_norm '00-F2-00-F1-45-ged-recherche-client-fixes-fixes')" "45-ged-recherche-client"
eq "v680: base nue inchangee"    "$(_norm '45-ged-recherche-client')" "45-ged-recherche-client"

# v6.81 (27/07: carte de reparation e2e ecrite a la main, probes tous deja verts (test -f
# de fichiers existants + gates qui passaient) => AUTODONE au semis, 13 specs restes rouges).
eq "v681: AUTODONE interdit aux reparations"  "$(grep -c "_no_autodone" loop/loop-overnight.sh)" "3"
eq "v681: motifs de reparation reconnus (v683: +2 sites dedup)" "$(grep -c '00-F\*|00-E2E\*|zz-E-\*' loop/loop-overnight.sh)" "4"
eq "v681: probes non discriminants signales"  "$(grep -c 'probes non discriminants' loop/loop-overnight.sh)" "2"
eq "v681: garde cablee au pick"               "$(grep -Fc 'if [ "$_no_autodone" = 0 ] && [ -n "$(runnable_probes' loop/loop-overnight.sh)" "1"
eq "v681: garde cablee en AUTODONE-LATE"      "$(grep -Fc 'if [ "${_no_autodone:-0}" = 0 ] && ! card_has_or_probes' loop/loop-overnight.sh)" "1"

# v6.82 (run 27/07: '00-F1-00-E2E-reparer-...-fixes'. v6.80 ne strippait que 00-F, donc les
# cartes 00-E2E/zz-E- derivaient encore: meme maladie, autre porte).
eq "v682: strip couvre 00-E2E"   "$(grep -Fc 's/^00-E2E-//' loop/loop-overnight.sh)" "1"
eq "v682: strip couvre zz-E-"    "$(grep -Fc 's/^zz-E-//' loop/loop-overnight.sh)" "1"
_n682(){ b="$1"; while :; do _l="$(printf '%s' "$b" | sed 's/^00-F[0-9]*-//; s/^00-E2E-//; s/^zz-E-//; s/-fixes$//')"; [ "$_l" = "$b" ] && break; b="$_l"; done; printf '%s' "$b"; }
eq "v682: 00-E2E normalisee"     "$(_n682 '00-E2E-reparer-suite')" "reparer-suite"
eq "v682: fix d'une 00-E2E converge" "$(_n682 '00-F1-00-E2E-reparer-suite-fixes')" "reparer-suite"
eq "v682: zz-E- normalisee"      "$(_n682 'zz-E-45-e2e-circuit')" "45-e2e-circuit"
eq "v682: base 00-F inchangee"   "$(_n682 '00-F1-45-ged-recherche-client-fixes')" "45-ged-recherche-client"

# v6.83 (regression de v6.81 vue au run post-merge du 27/07: une carte de reparation DEJA
# verte et mergee revenait a chaque run bruler un cycle, l'AUTODONE etant desormais ferme).
eq "v683: dedup reparation par historique"  "$(grep -c 'reparation. deja verte dans l.historique' loop/loop-overnight.sh)" "2"
eq "v683: cablee sur les 2 sites de semis"  "$(grep -c 'seed-dedup:' loop/loop-overnight.sh)" "4"
eq "v683: continue apres dedup sans-probe"  "$(sed -n '/deja vert et sans probe/,+2p' loop/loop-overnight.sh | grep -c 'continue')" "2"
eq "v683: memes motifs que v681"            "$(grep -c '00-F\*|00-E2E\*|zz-E-\*' loop/loop-overnight.sh)" "4"

# v6.84 (relecture du stack.sh d'un projet portage, 2 fuites d'identite dans la loi partagee corrigees a la source).
eq "v684: defauts verify surchargeables"    "$(grep -Fc 'BACK_PROC_PATTERN="${BACK_PROC_PATTERN:-' loop/verify.sh)" "1"
eq "v684: defaut pattern generique"         "$(grep -c 'BACK_PROC_PATTERN:-spring-boot' loop/verify.sh)" "1"
eq "v684: pattern projet porte par contrat" "$(grep -c '^BACK_PROC_PATTERN=' loop/stack.sh)" "1"
eq "v684: v661 conditionnee a la carte"     "$(sed -n '1500,1525p' loop/tests/harness-test.sh | grep -Fc 'if [ -f loop/tasks/42-auth-jwt-back.md ]')" "1"

echo "==== $PASS passed, $FAIL failed ===="
