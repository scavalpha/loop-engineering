#!/usr/bin/env bash
# lib.sh, shared functions of the loop law. Sourced by loop.sh, probe-lint.sh,
# verify.sh. No project knowledge here (anti-leak rule): everything stack-specific
# comes from loop/stack.sh.

# ---------- logging ----------
ts()  { date '+%H:%M:%S'; }
log() { echo "[$(ts)] $*"; }

# ---------- cards ----------

# card_probes <file>
# Print runnable probes, one per line. Strips "PROBE: " and markdown backticks.
# Neutralizes (skips, with a note on stderr) prose probes: a probe starting
# with a natural-language verb is not executable and would either never pass
# or, worse, make the driver revert good work.
card_probes() {
  local line p
  grep '^PROBE: ' "$1" 2>/dev/null | while IFS= read -r line; do
    p="${line#PROBE: }"; p="${p#\`}"; p="${p%\`}"
    [ -z "$p" ] && continue
    if printf '%s' "$p" | grep -qiE '^ *(verify|check|ensure|confirm|make sure|verifier|v\xc3\xa9rifier|cliquer|ouvrir|naviguer|s.assurer)'; then
      echo "NEUTRALIZED prose probe: $p" >&2
      continue
    fi
    printf '%s\n' "$p"
  done
}

# card_value <file> -> P0..P3 (default P2)
card_value() {
  local v
  v="$(grep -m1 '^VALUE:' "$1" 2>/dev/null | grep -oE 'P[0-9]')"
  printf '%s' "${v:-P2}"
}

# card_has_or_probes <file> -> rc 0 if any probe carries OR semantics.
# Two lying shapes, both seen shipping a card at birth:
#   - '|' alternation inside a quoted grep/rg pattern (true before the work)
#   - shell '||' between commands (second leg true since forever)
# Textual detection on raw PROBE lines: cheap, and blind spots of execution-
# based checks (rc>=2 neutralization) do not apply.
card_has_or_probes() {
  local l
  while IFS= read -r l; do
    [ -z "$l" ] && continue
    case "$l" in
      *"||"*) return 0 ;;
      *rg*\"*\|*\"*|*grep*\"*\|*\"*|*rg*\'*\|*\'*|*grep*\'*\|*\'*) return 0 ;;
    esac
  done < <(grep '^PROBE: ' "$1" 2>/dev/null)
  return 1
}

# card_always_true_probes <file> -> print offending raw lines ('|| true',
# '&& echo ... || echo ...'): unconditionally green probes.
card_always_true_probes() {
  grep -E '^PROBE: ' "$1" 2>/dev/null | grep -E '\|\| *true$|&& *echo .* \|\| *echo '
}

# is_repair_card <name-without-.md> -> rc 0 for fix-lot / e2e-repair / escalated.
# A repair card describes an OBSERVED defect: green probes on it mean bad
# probes, never a self-healed defect. The driver refuses AUTODONE for these.
is_repair_card() {
  case "$1" in
    00-F*|00-E2E*|zz-E-*) return 0 ;;
    *) return 1 ;;
  esac
}

# base_of <card-name> -> normalized base: strip EVERY repair prefix and every
# -fixes suffix, repeatedly, to a fixed point. Without the fixed point, gen 3
# of a fix was named 00-F1-00-F1-00-F1-<base>-fixes-fixes-fixes, each
# generation saw a fresh base and the generation cap never fired.
base_of() {
  local b="$1" prev
  while :; do
    prev="$b"
    b="$(printf '%s' "$b" | sed 's/^00-F[0-9]*-//; s/^00-E2E-//; s/^zz-E-//; s/-fixes$//')"
    [ "$b" = "$prev" ] && break
  done
  printf '%s' "$b" | tr -cd 'a-zA-Z0-9-'
}

# green_in_history <card-name> [git-dir] -> rc 0 if a commit "feat: <name> [loop"
# exists. History is the one honest exit for repair cards.
green_in_history() {
  local name="$1" dir="${2:-.}"
  git -C "$dir" log --format=%s 2>/dev/null | grep -q "^feat: $name \[loop"
}

# ---------- probes execution ----------

# run_probes <card-file> <workdir> [timeout]
# rc 0 if at least one runnable probe exists and ALL pass. rc 1 otherwise.
# Probes that would run a full e2e suite inline are skipped (short timeouts
# and sandboxes without ports make them guaranteed false reds): the suite
# belongs to the e2e phase.
run_probes() {
  local card="$1" wd="$2" tmo="${3:-30}" n=0 p
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in *"playwright test"*|*"loop/verify.sh --e2e"*) continue ;; esac
    n=$(( n + 1 ))
    ( cd "$wd" && timeout "$tmo" bash -c "$p" ) >/dev/null 2>&1 || return 1
  done < <(card_probes "$card" 2>/dev/null)
  [ "$n" -ge 1 ]
}

# probe_dry_lint <card-file> <workdir>
# Print one line per malformed probe (rc>=2 and not timeout): a command that
# cannot even parse can never turn green and silently voids a requirement.
probe_dry_lint() {
  local card="$1" wd="$2" p rc
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    case "$p" in *"playwright test"*|*"loop/verify.sh --e2e"*) continue ;; esac
    ( cd "$wd" && timeout 20 bash -c "$p" ) >/dev/null 2>&1; rc=$?
    if [ "$rc" -ge 2 ] && [ "$rc" != 124 ]; then
      echo "MALFORMED (rc=$rc, can never pass): $p"
    fi
  done < <(card_probes "$card" 2>/dev/null)
}

# ---------- misc ----------

# sanitize_utf8 <file>: drop invalid byte sequences in place. The codex CLI
# hard-rejects non-UTF-8 arguments (one truncated box-drawing character in a
# pasted log hard-failed every cycle that touched the card).
sanitize_utf8() {
  local f="$1" t
  t="$(mktemp)" || return 0
  iconv -f UTF-8 -t UTF-8 -c < "$f" > "$t" 2>/dev/null && mv "$t" "$f" || rm -f "$t"
}

# parse_deadline "<45m|2h|HH:MM>" -> epoch seconds
parse_deadline() {
  local a="$1" now h m
  now="$(date +%s)"
  case "$a" in
    *m) printf '%s' $(( now + ${a%m} * 60 )) ;;
    *h) printf '%s' $(( now + ${a%h} * 3600 )) ;;
    *:*)
      h="${a%%:*}"; m="${a##*:}"
      local t
      t="$(date -j -f '%H:%M' "$h:$m" +%s 2>/dev/null || date -d "$h:$m" +%s 2>/dev/null)"
      [ -n "$t" ] || { echo "bad deadline: $a" >&2; return 1; }
      [ "$t" -le "$now" ] && t=$(( t + 86400 ))
      printf '%s' "$t" ;;
    *) echo "bad deadline: $a (use 45m, 2h, or HH:MM)" >&2; return 1 ;;
  esac
}
