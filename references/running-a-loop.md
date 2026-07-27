# Running a loop

This is one worked way of pursuing a goal autonomously. It is not a procedure
to follow literally: build the harness that fits your project and your tools.
What matters is that each element below is covered somehow.

## Isolation

Work somewhere disposable, on its own branch. A git worktree is the usual
answer: the main checkout stays untouched, and a failed unit costs nothing but
a reset. This is what makes autonomous work safe enough to leave running.

Whatever you choose, make failure cheap. If undoing a bad unit of work is
expensive, you will be tempted to keep it.

## Rhythm

Each unit of work is a fresh start: a new sub-agent, its own context, thrown
away afterwards. Unit twelve must not inherit unit one's context, and a unit
that went badly must not poison the next.

Between units, the only things that persist are files: the cards, the commits,
the notes on what you learned. That is deliberate.

## Verdict

The unit is done when the project actually works, verified by execution. Then
either it becomes one commit, or the tree goes back to where it was. Keep the
diff of what failed: a rejected attempt is often nine tenths right, and
throwing it away means paying for it twice.

Do not accept a sub-agent's report as the verdict. It is a claim about its own
work. Check it.

## Being checked

Have your greens reviewed by a different model family, on the diff. Its
findings become the next unit of work, at top priority, and nothing gets
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

## Surviving a machine reboot

An agent session dies with its machine; nothing you do inside it changes that.
If a run must survive that, something outside must restart it: a system
scheduler waking you with your goal again. The state is safe regardless,
because the cards, the commits and the notes are files in git.
