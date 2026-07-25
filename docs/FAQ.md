# MacTweak — FAQ & Troubleshooting

Real questions that came up building and using MacTweak, with honest answers.

## General

### Do I need the app at all?
No. Every tweak is a plain Terminal command — see [TWEAKS.md](TWEAKS.md). The app
just wraps them with a live status probe, presets, a guided setup, and one-click
**Revert All**.

### Is it safe? Will it break my Mac?
Everything is **reversible** and verified against real macOS output. Safe tweaks are
cosmetic/performance; **moderate** and **advanced** ones are badged. On a SIP-enabled
Mac the riskiest system-daemon tweaks are simply **Unavailable**. See
[SAFETY.md](SAFETY.md).

### Which macOS does it need?
**macOS 15 or later** (uses Swift 6 / Swift Charts). Built and verified on macOS 26.

---

## Tweaks & state

### A tweak shows "Applied" but I didn't apply it.
The app reports the **real system state**, not what it did. If a value already matches
the applied state (e.g. Personalized Ads were already off), it correctly reads as
Applied. That's the probe working, not a bug.

### A tweak shows "Unavailable" and I can't toggle it.
It's **SIP-required** and your SIP is on. Check `csrutil status`. Either leave it
(recommended) or disable SIP — see [SAFETY.md](SAFETY.md).

### I applied a `sysctl` tweak and it's gone after reboot.
Expected. `sysctl` and `nvram` tweaks (GPU limit, TCP buffers, socket backlog, server
performance mode) live in memory/firmware and **reset on reboot** (♻️). Reapply to make
them stick.

### Turbo Key Repeat didn't change anything.
Log out and back in (or reboot). Key-repeat settings are read at login.

### The browser telemetry tweak shows a "managed by your organization" banner.
Expected — Chromium/Chrome/Brave/Edge honor these as **enterprise policies**, which
surfaces that note. It's cosmetic. Revert removes the policy and the banner.

---

## Performance & CPU

### Should I tune a MacBook Air differently from a Pro?
**Yes — four tweaks flip.** A fanless Mac sheds heat by *slowing down*, so its real
ceiling is thermal budget, and that budget is zero-sum with every background task.
In short: on an Air **subtract work** (disable background daemons, *Yield* the CPU
hogs, and leave the kernel's background-I/O brake on); on an actively-cooled Mac
you can afford to **add** (Unthrottle Background I/O and *Boost* have cooling
headroom behind them). **Server Performance Mode** belongs on a cooled desktop and
never on an Air — it costs SIP and a reboot for throughput you can't sustain.
Full reasoning and the per-tweak table: [TWEAKS.md](TWEAKS.md#fanless-vs-actively-cooled--yes-this-changes-what-you-should-apply).

### How do I tell whether my CPU is actually being throttled?
The Dashboard's **thermal card**. It reads macOS's own thermal-pressure level
(`Nominal` → the full clock range is available; `Fair`/`Serious`/`Critical` → macOS
is derating for heat), and **Check speed** samples real per-cluster frequencies
against the hardware maximum.

The trap to avoid: **cores sitting well below maximum is normal, not throttling** —
they clock down whenever nothing is asking for work. Only the pressure level tells
you the ceiling itself was lowered. From the terminal:
```bash
pmset -g therm                                    # Intel-era; says little on Apple Silicon
sudo powermetrics --samplers thermal -n 1         # "Current pressure level: Nominal"
sudo powermetrics --samplers cpu_power -n 1 -i 300 | grep "HW active frequency"
```
Note there is **no `hw.cpufrequency` on Apple Silicon** (it's Intel-only), which is
why frequency needs `powermetrics` and root. MacTweak derives each cluster's
maximum from the frequency-residency histogram in that output.

### I pruned Docker and the size barely moved. Did it work?
Almost certainly yes — the number you were looking at was the wrong one. `Docker.raw`
is a **sparse** file: it has a large *logical* size (the ceiling it may grow into) and a
much smaller *allocated* size (what it really occupies). `ls -lh` reports the ceiling,
which never shrinks:
```bash
F=~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw
ls -lh "$F" | awk '{print $5}'   # 60G  <- logical ceiling, always looks huge
du -h  "$F" | awk '{print $1}'   # 1.5G <- actually on disk
```
MacTweak reports the `du` figure. To see what a prune really freed, read its own last
line — `Total reclaimed space: …` (the app now shows it):
```bash
docker system prune -af --volumes
```
And unlike a cache row, **Docker won't reach `0B`.** Prune removes only *unused*
images, stopped containers, and anonymous volumes; whatever's left is live data plus
the guest filesystem's own overhead. `Total reclaimed space: 0B` means there was
nothing unused left to remove — not a failure.

### The app itself used a lot of CPU when idle. Is that fixed?
Yes. The cause was two things: per-second SwiftUI implicit animations on the
chart/rings (continuous recompositing, ~32% idle) and always-on metric sampling.
Fixed by removing those animations and **ref-counting sampling** (it only runs while a
gauge is on screen). Idle is now ~0% with no gauge visible.

### `coreaudiod` is pegging my CPU. What do I do?
A **third-party virtual-audio HAL driver** (commonly Microsoft Teams'
`MSTeamsAudioDevice.driver` in `/Library/Audio/Plug-Ins/HAL/`) can wedge a stream.
Those drivers run **inside** `coreaudiod`, so the cost bills there. Restart it:
```bash
sudo killall coreaudiod
```
It relaunches automatically (audio blips for a second). MacTweak's **Core Audio
Watchdog** can do this for you when `coreaudiod` stays hot for ~30 s — enable it on the
Dashboard (auto-restart is silent only if passwordless admin is unlocked).

**A restart is a symptom fix, not a cure.** launchd relaunches `coreaudiod`
immediately and the stuck plugin loads right back into it, so the same wedge often
returns within a minute. That's why the watchdog waits 5 minutes between restarts and
**gives up after three** — if it's still pegged, the plugin is the problem:
```bash
ls -la /Library/Audio/Plug-Ins/HAL/          # see what's installed
```
Quit the app that owns it (Teams is the usual culprit), or move the `.driver` bundle
out of that folder and restart `coreaudiod` once more. The watchdog keeps reporting
CPU after giving up; re-toggle it to try restarting again.

### What is `PerfPowerServices`? Is there a tweak for it?
It's Apple's **performance/power telemetry** helper — it periodically samples thermal
and power state to inform the scheduler and battery health. It's low-impact, bursty,
and **part of the OS's power management**; there's no safe, meaningful tweak for it,
so MacTweak doesn't ship one. Leave it alone.

### High CPU from `mlx`/Python processes?
That's **legitimate local inference** (MLX-LM), not waste — the model is doing work.
Not something to "optimize away."

### WindowServer spikes when I take screenshots.
Normal — screen capture drives WindowServer. Not a leak.

---

## The app "crashed" / disappeared

### I entered my admin password and the window vanished.
It almost certainly **didn't crash**. MacTweak is a menu-bar (accessory) app with no
Dock icon; when the macOS password dialog appears it steals focus, and afterward the
window can drop **behind** other windows — it *looks* gone but is alive in the menu
bar. This is now handled: after any auth dialog the app reactivates and raises its
window. If it ever truly crashes, `~/Library/Logs/MacTweak/MacTweak.log` records it.

### Where are the logs?
```bash
tail -f ~/Library/Logs/MacTweak/MacTweak.log
# or the unified log:
log show --predicate 'subsystem == "com.tanguy.MacTweak"' --last 30m
```

---

## Admin & privileges

### Why does it ask for my password?
Admin tweaks (`pmset`, `sysctl`, `mdutil`, system `launchctl`, `nvram`) need root.
MacTweak uses the **native macOS password dialog** — no helper tool, no stored
password. See [SAFETY.md](SAFETY.md).

### What is "Unlock passwordless admin"?
A one-time convenience: it installs a validated sudoers rule so later admin tweaks
skip the prompt. It grants your user passwordless root via `/bin/zsh` — **Lock** it
when done tuning if that concerns you. Manual removal: `sudo rm /etc/sudoers.d/mactweak`.

### Can I do the admin tweaks without unlocking anything?
Yes — run the `sudo` commands in [TWEAKS.md](TWEAKS.md) directly in Terminal.

---

## Uninstalling / resetting

### Undo everything.
In the app: **Revert All**. By hand: the **Revert** commands in [TWEAKS.md](TWEAKS.md),
or the emergency script (`bash ~/Documents/MacTweak_Revert.sh`).

### Remove the app's own settings and sudoers rule.
```bash
defaults delete com.tanguy.MacTweak 2>/dev/null   # onboarding/order/favorites
sudo rm -f /etc/sudoers.d/mactweak                 # passwordless-admin rule
```

See also: [TWEAKS.md](TWEAKS.md) · [SAFETY.md](SAFETY.md) · [ARCHITECTURE.md](ARCHITECTURE.md)
