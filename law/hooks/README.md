# Loop hooks (v5.7 N2, tool-layer hard-law)

INERT until the N2 milestone trial. reject-out-of-repo-write.sh is a Hermes
PostToolUse hook enforcing "maker writes stay inside the repo, never .git/ or loop/"
at the TOOL layer (stronger than the prompt-law constitution + PATH shims).

## N2 trial steps (do NOT skip validation)
1. `hermes hooks test PostToolUse` — learn the real payload JSON shape.
2. Fix the path-extraction in the hook if the field differs from the assumption.
3. Declare in ~/.hermes/config.yaml (event PostToolUse, matcher write_file/patch,
   command = this script, env LOOP_REPO_ROOT=<worktree>).
4. `hermes hooks doctor` (exec bit, allowlist, JSON, timing).
5. Throwaway run with a card that tries an out-of-repo write; confirm it's BLOCKED
   and a normal in-repo write PASSES.
Adopt only if forbidden writes become impossible AND normal writes are unaffected.
Rollback: `hermes hooks rm` + remove from config.yaml. Keep PATH shims regardless.
