#!/usr/bin/env bash
# v5.9 N2: write-boundary hook (pre_tool_call). Blocks file-tool writes OUTSIDE the loop
# worktree, plus writes into .git/ and loop/ inside it. Claude-Code-style permission layer.
#
# Hermes hook protocol (docs, fetched 2026-07-05): a hook BLOCKS by printing
#   {"decision":"block","reason":"..."}  to STDOUT.
# Non-zero exit codes NEVER block (they only log a warning) — the old v5.7 artifact that
# exited 1 to block was a silent no-op. Allow = print nothing, exit 0.
#
# Scope: file tools only (write_file/edit/patch/create). Terminal commands are not parsed
# here (documented limitation); worktree isolation + the gate remain the net for those.
# LOOP_REPO_ROOT is baked into the hook's env by setup-hermes-profile.sh via config.yaml.
set -u
REPO="${LOOP_REPO_ROOT:-}"
[ -n "$REPO" ] || exit 0                    # unconfigured => allow (never brick the maker)
payload="$(cat 2>/dev/null || true)"
path="$(printf '%s' "$payload" | python3 -c "
import json,sys
try:
    d=json.load(sys.stdin); ti=d.get('tool_input') or {}
    print(ti.get('path') or ti.get('file_path') or ti.get('filepath') or '')
except Exception:
    print('')" 2>/dev/null)"
[ -n "$path" ] || exit 0                    # not a path-bearing call => allow
case "$path" in
  /*) abs="$path" ;;
  *)  abs="$REPO/$path" ;;
esac
# normalize without requiring the file to exist
norm="$(python3 -c "import os,sys; print(os.path.normpath(sys.argv[1]))" "$abs" 2>/dev/null || printf '%s' "$abs")"
case "$norm" in
  "$REPO"/.git/*|"$REPO"/loop/*)
    printf '{"decision":"block","reason":"write to protected path %s (harness-owned: .git/, loop/)"}' "$path"
    exit 0 ;;
  "$REPO"/*)
    exit 0 ;;                               # inside the worktree => allow
  *)
    printf '{"decision":"block","reason":"write outside the project folder: %s. The project worktree is %s; reading outside is fine, writing is not."}' "$path" "$REPO"
    exit 0 ;;
esac
