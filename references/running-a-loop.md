# Running a loop

This is one worked way of pursuing a goal autonomously. It is not a procedure
to follow literally: build the harness that fits your project and your tools.
What matters is that each element below is covered somehow.

## Project boundary

Work directly in the exact project folder the owner supplied or opened, on its
current branch or a local branch in that checkout. Do not create another clone
or a worktree. The owner may explicitly request a worktree for a particular
run; only then create it, and only inside the same project folder.

Preflight this before starting: resolve the Git top-level, inspect and preserve
existing changes, and prove the folder and Git metadata are writable for the
full authorized window. If any of that fails, stop before the first card. Do
not relocate the project or start a run that will need an approval prompt
midway through its supposedly autonomous window.

Contain caches, logs, reports, and temporary artifacts inside the project in
ignored paths. The parent folder, sibling folders, other workspaces, and the
home directory belong to the owner, not to the loop.

Make failure cheap with atomic commits and reviewed restoration of loop-owned
changes. Never reset, stash, hide, or discard pre-existing owner work.

## Rhythm

Each unit of work is a fresh start: a new sub-agent, its own context, thrown
away afterwards. Unit twelve must not inherit unit one's context, and a unit
that went badly must not poison the next.

Between units, the only things that persist are files: the cards, the commits,
the notes on what you learned. That is deliberate.

Pass a new sub-agent a role-sized packet from those artifacts, never the raw
conversation as a substitute for a handoff. A maker needs its card, base,
affected contracts and gates. A repair maker needs only the judge's remaining
predicate, preserved behaviour, relevant diff and failing proof. The final
judge needs the whole accumulated diff, cards, commits and executed evidence.
This keeps a fresh start bounded without hiding the information each role
actually needs.

## Verdict

The unit is done when the project actually works, verified by execution. Then
either it becomes one commit, or the tree goes back to where it was. Keep the
diff of what failed: a rejected attempt is often nine tenths right, and
throwing it away means paying for it twice.

Do not accept a sub-agent's report as the verdict. It is a claim about its own
work. Check it.

When a unit fails, classify before reacting, in this order: infrastructure
(overload, quota, network, a saturated machine) is never the card's fault,
pause and retry the same card unchanged; a real red banks the diff, resets,
and the next attempt goes to a different model, same model means same blind
spot; the same cause seen twice stops the run's work entirely, because the
fault is upstream, in a stale spec or a check that lies.

## Being checked

At close, have the run's accumulated diff reviewed by a different model
family — the whole diff, not card by card: the defect that survives a per-card
review is exactly the one that only appears once the cards sit together. Its
findings become the next units of work, at top priority, and nothing gets
reverted: the code already passed its checks, so refine it forward.

If only one family is available, say so in the report rather than implying a
review happened.

## Watching a run

Look often at the start, then at each outcome. What you are watching for:

- **Two failures with the same cause.** Stop and diagnose. Pushing through
  burns the window and produces nothing.
- **A long silence.** Something is stuck, waiting on a port, or dead.
- **A red that contradicts a recent green.** Suspect the machine before the
  code: memory pressure kills backends mid-suite, and the failures look
  exactly like real regressions.
- **Anything a safety net absorbed.** A net catching a problem is still a
  problem. Diagnose it now, not tomorrow.

## Closing

Verify the whole thing independently, on a quiet machine: per-unit checks
never see assembly breakage. Then report what is mergeable and let the owner
merge. Kill everything you started, including sub-agents that outlived their
orchestrator: they keep writing with nobody left to judge them.

The same rule holds for the disk. Closing means leaving it the way the owner
agreed: the footprint back in its one place, temporary files gone, caches and
directories the next run does not need removed. A run that ends green but
leaves debris is not finished, and if an earlier run scattered something, the
run that notices is the run that cleans it.

## Surviving a machine reboot

An agent session dies with its machine; nothing you do inside it changes that.
If a run must survive that, something outside must restart it: a system
scheduler waking you with your goal again. A restart inside the window the
owner ordered is the same run, not a new decision; past the deadline, nothing
relaunches itself, and a scheduler entry that outlives its own deadline is an
incident to remove. The state is safe regardless, because the cards, the
commits and the notes are files in git.
