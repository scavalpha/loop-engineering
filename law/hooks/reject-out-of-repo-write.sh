#!/usr/bin/env bash
# v5.7 N2 TRIAL ARTIFACT — NOT ACTIVATED. Tool-layer hard-law (ECC-inspired).
# A Hermes PostToolUse hook that rejects a maker write outside the repo worktree.
# Before wiring into ~/.hermes/config.yaml, validate the payload shape:
#     hermes hooks test PostToolUse
# then confirm which JSON field carries the target path (assumed .tool_input.path
# / .path below — ADJUST to the real schema). Nonzero exit blocks the tool call.
set -uo pipefail
REPO="${LOOP_REPO_ROOT:?set to the loop worktree root}"
payload="$(cat)"
path="$(printf '%s' "$payload" | python3 -c "import json,sys
try:
    d=json.load(sys.stdin); print(d.get('tool_input',{}).get('path') or d.get('path') or '')
except Exception: print('')" 2>/dev/null)"
[ -z "$path" ] && exit 0                    # not a path-bearing tool call, allow
case "$path" in
  /*) abs="$path" ;;                         # absolute
  *)  abs="$REPO/$path" ;;                   # relative to repo
esac
real="$(cd "$(dirname "$abs")" 2>/dev/null && pwd)/$(basename "$abs")" || real="$abs"
case "$real" in
  "$REPO"/*)
     case "$real" in
       "$REPO"/.git/*|"$REPO"/loop/*) echo "BLOCKED: write to protected path $path" >&2; exit 1 ;;
       *) exit 0 ;;                           # inside repo, outside .git/loop => allow
     esac ;;
  *) echo "BLOCKED: write outside repo: $path" >&2; exit 1 ;;
esac
