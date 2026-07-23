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
