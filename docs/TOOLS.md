# Tools — the panes that aren't tweaks

tweakd's toggle catalog is documented in [TWEAKS.md](TWEAKS.md) and the Services page
has its own guide in [SERVICES.md](SERVICES.md). This page covers **everything else**:
Dashboard, Disk Cleanup, Process Priority, Thermal, Benchmark, the audio watchdog, and
the audit trail — with the exact Terminal command for each, so none of it needs the app.

Commands marked **🔐** need `sudo`. Everything else runs as you.

---

## Contents

- [Dashboard — live CPU, memory, Clear RAM](#dashboard--live-cpu-memory-clear-ram)
- [Thermal & CPU speed](#thermal--cpu-speed)
- [Disk Cleanup](#disk-cleanup)
- [Orphaned app leftovers](#orphaned-app-leftovers)
- [Process Priority](#process-priority)
- [Benchmark & history](#benchmark--history)
- [Core Audio Watchdog](#core-audio-watchdog)
- [The audit trail](#the-audit-trail)

---

## Dashboard — live CPU, memory, Clear RAM

The gauges read the Mach kernel directly rather than shelling out, so there's no exact
one-liner equivalent — but these get you the same numbers.

```bash
# CPU, honestly: a rolling sample, not a single frame
/usr/bin/top -l 2 -n 0 -s 1 | /usr/bin/grep "CPU usage" | /usr/bin/tail -1

# Memory pressure — the number that actually matters, not "free RAM"
/usr/bin/memory_pressure | /usr/bin/tail -3
/usr/bin/vm_stat
```

**Clear RAM** (the button on the memory ring) purges inactive pages:

```bash
sudo /usr/sbin/purge          # 🔐
```

> **What "Clear RAM" is and isn't.** It flushes the disk cache and compresses/evicts
> inactive pages. Free memory goes up, and then everything that needed those cached
> pages reads them off disk again — so the machine is briefly *slower*, not faster.
> Useful before a big build that wants a clean slate; pointless as routine hygiene.
> macOS has no equivalent of a Windows "RAM cleaner", and unused RAM is wasted RAM.

**System facts** shown on the card:

```bash
/usr/sbin/sysctl -n machdep.cpu.brand_string hw.ncpu hw.memsize
/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/head -12
/usr/bin/uptime
```

---

## Thermal & CPU speed

Answers "am I being throttled, or is the Mac just idle?" — two different measurements
that look identical in a CPU graph.

**1. Thermal pressure** — macOS's own throttle signal, and the authoritative one. The app
reads `ProcessInfo.thermalState`, which has **no free command-line equivalent**. The
honest options:

```bash
# The real thing — needs root. Look for "Current pressure level"
sudo /usr/bin/powermetrics --samplers thermal -n 1 -i 300      # 🔐

# Free, but on Apple Silicon it usually reports nothing at all:
/usr/bin/pmset -g therm
```

On this M2 Air `pmset -g therm` prints only `No thermal warning level has been
recorded` — it reflects the older CPU-speed-limit mechanism, not the pressure level, so
**don't read "no warning" as "not throttled."** Use `powermetrics`, or the app's card.

Levels are **nominal** (full speed available) · **fair** (slightly limited) ·
**serious / critical** (real loss of performance).

**2. Actual clock speeds** — needs root, takes ~0.3 s:

```bash
sudo /usr/bin/powermetrics --samplers cpu_power -n 1 -i 300   # 🔐
```

Look for the per-cluster `E-Cluster HW active frequency` and `P-Cluster HW active
frequency` lines, and compare them to the hardware maximum:

```bash
/usr/sbin/sysctl -n hw.cpufrequency_max 2>/dev/null    # empty on Apple Silicon
/usr/sbin/system_profiler SPHardwareDataType | /usr/bin/grep -i chip
```

> **Cores clocking below maximum is normal.** They clock down when there's nothing to do.
> Low frequency **plus** nominal thermal pressure means idle. Low frequency **plus**
> serious pressure means throttled. Only the second one is a problem, and on a fanless
> Air the fix is removing work, not adding tweaks — see
> [TWEAKS.md](TWEAKS.md#fanless-vs-actively-cooled--yes-this-changes-what-you-should-apply).

Watch it live while you reproduce a slowdown:

```bash
sudo /usr/bin/powermetrics --samplers cpu_power,thermal -i 1000    # 🔐  Ctrl-C to stop
```

---

## Disk Cleanup

Every row on the page is a `du` to measure and one command to clear. **Measure first** —
the size command is always safe to run.

| Row | Measure | Clear |
|---|---|---|
| **Empty Trash** | `du -sh ~/.Trash` | `osascript -e 'tell application "Finder" to empty trash'` |
| **App Caches** | `du -shc $(find ~/Library/Caches -mindepth 1 -maxdepth 1 -not -iname 'com.apple.*') \| tail -1` | `find ~/Library/Caches -mindepth 1 -maxdepth 1 -not -iname 'com.apple.*' -exec rm -rf {} +` |
| **Xcode DerivedData** | `du -sh ~/Library/Developer/Xcode/DerivedData` | `rm -rf ~/Library/Developer/Xcode/DerivedData/*` |
| **Old iOS Device Support** | `du -sh ~/Library/Developer/Xcode/iOS\ DeviceSupport` | `rm -rf ~/Library/Developer/Xcode/iOS\ DeviceSupport/*` |
| **Simulator Caches** | `du -sh ~/Library/Developer/CoreSimulator/Caches` | `rm -rf ~/Library/Developer/CoreSimulator/Caches/*` |
| **Unavailable Simulators** | `xcrun simctl list devices unavailable` | `xcrun simctl delete unavailable` |
| **Homebrew Cache** | `du -sh "$(brew --cache)"` | `brew cleanup -s` |
| **npm Cache** | `du -sh ~/.npm` | `npm cache clean --force` |
| **pip Cache** | `du -sh ~/Library/Caches/pip` | `pip cache purge` |
| **Crash & Diagnostic Reports** | `du -sh ~/Library/Logs/DiagnosticReports` | `rm -rf ~/Library/Logs/DiagnosticReports/*` |
| **QuickLook Thumbnails** | — | `qlmanage -r cache; qlmanage -r` |
| **iOS Device Backups** | `du -sh ~/Library/Application\ Support/MobileSync/Backup` | *reveal only — never auto-deleted* |
| **Docker Data** | `du -h ~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` | `docker system prune -af --volumes` |

Measure everything at once:

```bash
/usr/bin/du -sh ~/.Trash ~/Library/Caches ~/Library/Developer/Xcode/DerivedData \
  ~/Library/Logs/DiagnosticReports ~/.npm 2>/dev/null
```

### Three things worth knowing before you clear

**`du`, not `ls -lh`, for Docker.** `Docker.raw` is a **sparse file**: `ls` reports the
size it may *grow into* (60 GB on a machine using 1.5 GB) — a number that never shrinks
no matter how much you prune. `du` counts blocks actually allocated. Compare them:

```bash
/usr/bin/stat -f "logical=%z allocated=%b blocks" ~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw
```

**Docker prune needs Docker running.** If Docker Desktop is stopped, `docker system
prune` fails — tweakd deliberately does *not* mask that error, so a failed prune
reports as failed rather than "done" while freeing nothing.

**Clearing a cache does not remove work — it defers it.** Every wiped cache is rebuilt on
next use, and the rebuild costs CPU, disk and heat *now*. Wiping DerivedData means your
next build is a full one. On a fanless Mac a big cleanup is reliably followed by a warm,
busy half-hour; that's the cleanup, not a tweak that went wrong. See
[FAQ.md](FAQ.md#performance--cpu).

---

## Orphaned app leftovers

Support files left behind by apps you've deleted. The app scans six directories and
matches each entry against installed apps; the equivalent by hand:

```bash
for d in ~/Library/Caches ~/Library/Application\ Support ~/Library/Saved\ Application\ State \
         ~/Library/HTTPStorages ~/Library/WebKit ~/Library/Containers; do
  /bin/ls -1 "$d" 2>/dev/null
done | /usr/bin/sort -u | /usr/bin/head -50
```

Then check whether the owning app still exists in `/Applications` or `~/Applications`
before deleting anything. **Read the list before you act** — bundle IDs don't always
resemble the app's name, and a few belong to system components rather than apps.

---

## Process Priority

Full documentation, including the curated targets and the "apply at login" LaunchAgents,
is in [TWEAKS.md § Process Priority](TWEAKS.md#-process-priority). The essentials:

```bash
# What's busiest right now (what the page's table shows)
/bin/ps -Ao pid=,nice=,%cpu=,comm= -r | /usr/bin/head -15

# Current nice value of one process
/bin/ps -o nice= -p <pid>

# Make something yield CPU (positive nice — no sudo needed to lower priority)
renice -n 10 -p <pid>

# Give something priority (negative nice — needs root)
sudo renice -n -5 -p <pid>          # 🔐

# Every process matching a name
sudo renice -n -5 -p $(/usr/bin/pgrep -f "Google Chrome")   # 🔐

# Reset to normal
sudo renice -n 0 -p <pid>           # 🔐
```

Nice runs **−20 (highest priority) to +20 (lowest)**; the app clamps to a safer range.
Raising priority is rarely the win people expect — on a machine that's already CPU-bound,
*lowering* a background hog does more than boosting the foreground app.

---

## Benchmark & history

The four workloads are compiled into the app (a shell script can't measure single-core
integer throughput meaningfully), but the **results are plain JSON** and yours to read:

```bash
/bin/cat ~/Library/Application\ Support/tweakd/benchmark-history.json
```

```json
[
  {
    "date" : "2026-07-26T12:00:04Z",
    "disk" : 9600.4,
    "id" : "…",
    "memoryBandwidth" : 101000.2,
    "multiCore" : 441.2,
    "singleCore" : 82.4,
    "trigger" : "scheduled"
  }
]
```

Pretty-printed, ISO-8601 dates, sorted keys, capped at the most recent 400 runs.
Scores are `singleCore×4 + multiCore×1.5 + memory×0.02 + disk×0.05`.

Plot or summarise it without the app:

```bash
# every run, as date + overall score
/usr/bin/python3 -c 'import json,sys;[print(r["date"][:10], round(r["singleCore"]*4+r["multiCore"]*1.5+r["memoryBandwidth"]*0.02+r["disk"]*0.05)) for r in json.load(open(sys.argv[1]))]' \
  ~/Library/Application\ Support/tweakd/benchmark-history.json
```

**Rough shell equivalents** if you want a sanity check outside the app:

```bash
# Disk write+read throughput (~1 GB, writes to /tmp)
/bin/dd if=/dev/zero of=/tmp/bench.bin bs=1m count=1024 2>&1 | /usr/bin/tail -1
/bin/dd if=/tmp/bench.bin of=/dev/null bs=1m 2>&1 | /usr/bin/tail -1; /bin/rm /tmp/bench.bin

# Single-core, very rough
/usr/bin/time /usr/bin/openssl speed -seconds 1 sha256 2>/dev/null | /usr/bin/tail -3
```

These are **not** comparable to tweakd's scores — different work, different scale. Use
them for "is the disk suddenly slow", not for tracking a trend.

### The daily run

Configured in the app (**Benchmark → Daily Benchmark**, default 12:00, off until you
enable it). It's an in-app timer, so it only fires while tweakd is running, and it is
**postponed while the Mac is warm or busy** and **skipped entirely if more than 4 hours
late** — a benchmark taken mid-build measures the build. Details and reasoning in
[FAQ.md § Benchmark](FAQ.md#benchmark).

Check whether it's on, and when:

```bash
defaults read app.tweakd benchmark.daily      # 1 = on
defaults read app.tweakd benchmark.dailyHour  # hour of day
```

---

## Core Audio Watchdog

A third-party virtual-audio driver (Teams', typically) can wedge a stream and peg
`coreaudiod` — the driver runs *inside* `coreaudiod`, so the CPU bills there. Check by
hand with a **cputime delta**, which is the only honest measure:

```bash
P=$(/usr/bin/pgrep -x coreaudiod)
/bin/ps -o cputime= -p $P; sleep 10; /bin/ps -o cputime= -p $P
```

More than ~7 seconds of CPU accumulated over those 10 s means it's spinning ~70% of a
core, which is the app's trip threshold. **Legitimate** work — a call with echo
cancellation or spatial audio — sustains 10–30%, so don't act on a lower number.

Restart it (launchd relaunches it immediately):

```bash
sudo /usr/bin/killall coreaudiod        # 🔐  audio blips for ~1 s
```

> **If it wedges again within a minute, restarting is not the fix.** The offending plugin
> reloads into the fresh process, and you'll loop forever. Find the plugin and remove it:
> ```bash
> /bin/ls -1 /Library/Audio/Plug-Ins/HAL ~/Library/Audio/Plug-Ins/HAL 2>/dev/null
> ```
> The app's watchdog gives up after 3 attempts for exactly this reason and tells you the
> same thing rather than flapping.

Toggle state:

```bash
defaults read app.tweakd watchdog.coreaudio    # 1 = watching
```

---

## The audit trail

**Every change tweakd makes** is recorded with its before state, its intended state,
and the **verified actual** state afterwards — including the ones that failed.

```bash
/usr/bin/log show --predicate 'subsystem == "app.tweakd" AND category == "audit"' --last 24h
```

```
CHANGE event=tweak.set key=disable-siri-daemon from=notApplied to=applied result=ok exit=0
```

`result=` is one of **ok** (verified in the new state) · **failed** (ran, system didn't
move) · **cancelled** (auth dismissed) · **skipped** (nothing to do).

Useful filters:

```bash
# just services
… --last 7d | /usr/bin/grep service.

# just the things that didn't work
… --last 7d | /usr/bin/grep 'result=failed'

# benchmark runs and skipped days
… --last 7d | /usr/bin/grep benchmark
```

There's also a plain file, which survives a crash the unified log wouldn't record:

```bash
/usr/bin/tail -50 ~/Library/Logs/tweakd/tweakd.log
```

> **This is the answer to "what is actually applied right now?"** — not
> [SYSTEM-CHANGES.md](../SYSTEM-CHANGES.md), which is a frozen record of one 2026-07-22
> testing session. Use the app's **Re-scan**, or read the trail.

Note the `log` shell alias trap: many setups alias `log` to a `git log` command, which
silently returns git history instead of an error. Call `/usr/bin/log` explicitly, as
above.

---

## See also

- **[TWEAKS.md](TWEAKS.md)** — all reversible tweaks + one-shot actions.
- **[SERVICES.md](SERVICES.md)** — background services: tutorial and `launchctl` cookbook.
- **[SAFETY.md](SAFETY.md)** — privileges, SIP, the emergency revert script.
- **[FAQ.md](FAQ.md)** — troubleshooting.
