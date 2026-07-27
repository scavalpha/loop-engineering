# Supervision: launch, watch, close

The loop is autonomous per cycle, never per night. The operator doctrine is
three sentences: no run without an explicit owner order, supervise every run,
diagnose every anomaly immediately even when a safety net already absorbed it.

## Launch

Foreground, first runs, always supervised:

```bash
bash loop/loop.sh 1h
```

Background with a log you actually watch:

```bash
nohup bash loop/loop.sh 6h > loop/logs/nohup-$(date +%H%M).log 2>&1 &
tail -f loop/logs/run-*.log
```

Overnight on macOS, launchd is more reliable than nohup for detached runs.
Two hard-won rules if you use it:

- `launchctl bootout` does NOT survive a reboot: if the plist file remains in
  `~/Library/LaunchAgents`, launchd reloads it at boot. A stale plist with a
  past deadline re-launched a finished run, and the driver read "23:26
  yesterday" as "23:26 tonight", a 24-hour zombie. At close: bootout AND
  delete the plist.
- Give the job its own log file per run, and grep it, do not trust silence.

## What to watch

The run log is greppable by design:

```bash
tail -n 0 -F loop/logs/run-*.log | grep -E --line-buffered \
  'CYCLE|GREEN|RED|AUTODONE|REFUSE|PAUSE|STERILE|CLOSE'
```

| Line | Meaning | Your reaction |
| --- | --- | --- |
| `GREEN <sha>` | card shipped, gates passed | none |
| `RED gate` / `RED probes` | work reset, patch banked | none if isolated, investigate if repeated on one card |
| `AUTODONE` | probes already pass, card retired | spot-check honesty on the first few |
| `REFUSED autodone (repair card)` | discriminance guard fired | check the card's probes, they may be scenery |
| `PAUSE overloaded/network/quota` | infra class, card preserved | none, verify it resumes |
| `STERILE` | 5+ cycles, zero green | read the last cycle logs NOW, something structural is wrong |
| `REFUSE` at preflight | red base, busy port, dead agent | fix the cause, relaunch, never force |

Cadence: look every 10 minutes for the first half hour, then each GREEN/RED.
The expensive failure mode is build-and-revert in a loop: the maker does good
work, one bad probe reverts it, forever. Only a human notices this early.

## Failure classes cheat sheet

Before blaming a card or a model, classify:

| Symptom | Likely class | Check |
| --- | --- | --- |
| Failure after minutes of good work, `529` or `overloaded` in cycle log | provider saturated | driver pauses 3 min and retries, cap 3 per run |
| Two instant failures in a row | dead CLI, quota, wrong model name | ping the agent CLI by hand |
| `ECONNREFUSED` plus provider endpoint down | network | driver waits in slices |
| e2e red that contradicts a recent green | machine saturation | `vm_stat`, swap usage, top RSS. Re-verify quiet |
| Same card red across runs with rc=2 probes | malformed probe | run the probe by hand, fix the card |
| Cards named `00-F1-00-F1-...` piling up | fix-churn, cap not firing | check lot-gen counters, normalize names |

## Close

A run ends at deadline, on queue-complete, or on `touch loop/STOP` (honored
after the current cycle). The driver then reaps and reports. Your close
checklist, in order:

1. Driver really exited (`pgrep -f loop.sh`), plus scheduler entry removed
   AND its config file deleted if you used one.
2. No orphans: no JVM, dev server, node or headless browser pointing into
   the worktree. Ports of the stack are free.
3. Read `loop/state/report-<run>.md`: greens, reds, pauses, anomalies. Every
   anomaly gets a diagnosis now, even the ones a net absorbed.
4. Independent verification before merge: run the gates and the FULL e2e
   yourself, on a quiet machine. Do not merge on the maker's word: a status
   file is a claim.
5. Merge is the owner's act: `git merge --no-ff loop/work` into the base,
   with a message summarizing what was verified.

## Machine hygiene

Runs are heavy: maker sessions, builds, test JVMs, headless browsers. Learned
the hard way:

- Concurrent daytime use (IDE compiling, browser with 50 tabs, VMs) plus a
  run can exhaust RAM and swap. The visible symptom is a backend OOM-killed
  mid-suite: a false red that looks exactly like a regression. Prefer night
  runs, or verify on a quiet machine before believing a red.
- If reboots without kernel traces occur during runs, suspect hardware or
  thermal pressure before software: log load and temperature each minute to
  a persistent ledger and compare against reboot times before theorizing.
  Correlation with whatever tool ran last is usually survivorship bias.
- Headless Chromium on Apple Silicon: keep GPU off in every launch path.
