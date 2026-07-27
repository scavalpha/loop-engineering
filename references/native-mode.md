# Native mode: the loop without a driver process

The bash driver buys you unattended nights. It costs you plumbing: a detached
process to launch, a PID to find (it runs from a copy of itself in /tmp, so
naive `pgrep` misses it), a risk of two drivers colliding on one worktree, and
log files to tail. Every one of those has bitten in production.

Native mode removes the plumbing entirely: the agent IS the driver. Same
doctrine, same cards, same gates, no process to babysit.

## The loop, executed by you

Repeat until the stop condition holds:

1. **Pick** the highest-priority card: VALUE P0 first, then filename order.
   The queue is just files in `loop/state/queue/` (or `loop/tasks/`).
2. **Check discriminance**: run the card's PROBES now. If they ALL pass
   already, do not do the work: either the feature landed earlier (retire the
   card) or, for a repair card, the probes are bad (fix the card, say so).
3. **Execute in a SUB-AGENT**, working in the worktree, with the card, the
   `STACK_BRIEF` and the gate commands in its prompt. The sub-agent is what
   keeps contexts isolated: card 15 must not inherit card 1's context. Never
   execute cards inline in your own context on a long run.
4. **Judge yourself**, never on the sub-agent's word: run the gate commands
   from `stack.sh`, then the card's PROBES.
5. **Commit or reset**, atomically:
   - green: `git -C <worktree> add -A && git commit -m "feat: <card> [loop]"`,
     move the card to `loop/state/done/`
   - red: bank the diff (`git diff > loop/wip/<card>.patch`), then
     `git reset --hard && git clean -fd -e loop`. Retry once with a different
     model if you have one, then park it in `loop/state/failed/`.
6. **Review the green** with the OTHER model family if you have one. Findings
   become a `00-F<gen>-<base>-fixes` card, VALUE P0, and nothing is reverted.
7. **Report** one line per card in `loop/state/report-<run>.md`.

Stop when: the queue has no P0 left AND the full runtime suite passes, or the
owner's time budget is spent, or two consecutive cards fail for the same
reason (that is a signal, not bad luck: stop and diagnose).

## Holding the intent across turns

Use the agent's own goal feature, with a stop condition that is a command,
never an opinion:

```
/goal Work the loop on this repo: pick the highest-priority card from
      loop/state/queue, execute it in a sub-agent inside the worktree, run
      the gates, commit if green else git reset --hard, repeat until
      `bash loop/verify.sh` exits 0 and no P0 card remains in the queue.
      Never mark a card done on the sub-agent's word.
```

If the session dies, the state is not lost: the cards are files in git, the
done ones moved, the greens committed. Reopen and continue. That is the whole
point of writing goals into cards instead of a database.

## What you gain, what you owe

**Gained**: no detached process, no PID hunting, no two-drivers collision, no
log tailing. Failures are visible immediately, in the conversation. Setup is
zero.

**Owed**, and this is the real cost: the discipline is now yours. A shell
script cannot talk itself into accepting bad work; you can. Three rules to
hold, especially late in a long session:

- Never mark a card done because the sub-agent said so. Run the gates.
- Never weaken a probe to make a card pass. Fix the code or fix the card
  honestly, and say which you did.
- Never skip the reset on red. Half-applied work is how a codebase rots.

If you notice yourself rationalising any of those, that is the moment to stop
and hand back to the owner.

## When to use which mode

| | Native mode | Driver mode |
| --- | --- | --- |
| Unattended 7-hour night | no | yes |
| Short supervised session | yes | works, heavier |
| Zero setup | yes | needs install |
| Survives machine reboot | needs a restart by someone | resurrector restarts it |
| Discipline enforced by | you | the script |
| Debugging a failure | immediate, in conversation | read the logs |

Start native to learn the doctrine on a real project. Move to the driver when
you want the machine to work while you sleep.
