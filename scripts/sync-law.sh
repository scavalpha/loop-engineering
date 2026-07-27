#!/usr/bin/env bash
# sync-law.sh, re-vendor the shared law into a project that already has loop/.
# Usage (from the project root):  bash <skill>/scripts/sync-law.sh
# Never touches loop/stack.sh (your contract) nor loop/tasks, state, logs, wip.
set -u
SKILL="$(cd "$(dirname "$0")/.." && pwd)"
[ -d loop ] || { echo "no loop/ here: use init-loop.sh first"; exit 1; }
HAVE="$(cat loop/LAW-VERSION 2>/dev/null || echo unknown)"
WANT="$(cat "$SKILL/law/LAW-VERSION")"
echo "law: $HAVE -> $WANT"
for f in "$SKILL"/law/*.sh "$SKILL"/law/*.mjs "$SKILL"/law/*.md "$SKILL"/law/LAW-VERSION; do
  [ -f "$f" ] || continue
  cp "$f" "loop/$(basename "$f")"
done
mkdir -p loop/tests && cp "$SKILL"/law/tests/*.sh loop/tests/ 2>/dev/null
chmod +x loop/*.sh loop/tests/*.sh 2>/dev/null
echo "law synced. Your loop/stack.sh, tasks/ and state/ were left untouched."
echo "Verify: bash loop/tests/harness-test.sh"
