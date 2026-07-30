# tweakd Documentation

Everything about tweakd — the app, and how to do all of it **by hand** in Terminal.

## Start here

- **[index.html](index.html)** — the web docs. Every tweak with its exact Apply/Revert
  command and **click-to-copy**. Open it in a browser (works offline).
- **[TWEAKS.md](TWEAKS.md)** — the same reference in Markdown: every tweak + the one-shot
  actions, grouped by category, with manual commands.

## The tools (everything that isn't a toggle)

- **[SERVICES.md](SERVICES.md)** — background services, start to finish: what launchd
  domains are, a **step-by-step tutorial** for finding and stopping something you don't
  need, the full `launchctl` cookbook (list · find failing · inspect · measure cost ·
  stop · disable · restart), what not to touch, and what each `launchctl` error means.
- **[TOOLS.md](TOOLS.md)** — command-line equivalents for the remaining panes: Dashboard
  and Clear RAM, Thermal & CPU speed, every Disk Cleanup row, Process Priority, Benchmark
  history (the JSON is yours to read), the Core Audio watchdog, and the audit trail.

## Reference

- **[SAFETY.md](SAFETY.md)** — privileges (`sudo`), System Integrity Protection (SIP),
  reversibility, the emergency revert script, and how to verify changes yourself.
- **[FAQ.md](FAQ.md)** — troubleshooting: stopping background services (MySQL/PHP/nginx)
  and proving detection is complete, the recurring VoiceOver dialog, high CPU and how to
  measure it honestly, `coreaudiod`, why cleaning makes a Mac hot, Docker sparse-file
  sizing, tuning an Air vs. a Pro, where benchmark history lives and why the daily run
  skips a busy Mac, "the app disappeared", passwordless admin, uninstalling.
- **[ARCHITECTURE.md](ARCHITECTURE.md)** — how the app is built (SwiftUI, TweakEngine,
  CommandRunner escalation, Mach metrics, **ServicesManager and how it detects *every*
  background service**, watchdog, logging, theme).

## Project root

- **[../README.md](../README.md)** — project overview & install.
- **[../CONTRIBUTING.md](../CONTRIBUTING.md)** — build, and how to add a tweak safely.
- **[../CHANGELOG.md](../CHANGELOG.md)** — version history.
- **[../SYSTEM-CHANGES.md](../SYSTEM-CHANGES.md)** — log of settings changed on the dev
  Mac during the 2026-07-22 testing session (all of those reverted). Not a live
  inventory — read the audit trail for what is actually applied now.

## The one-paragraph version

tweakd is a premium **menu-bar app for macOS 15+** that toggles **reversible** system
optimizations — Performance, Power, Snappiness, Privacy, Background Services, Network,
AI. It drives plain `defaults` / `pmset` / `sysctl` / `launchctl` / `mdutil` / `nvram`
commands (all documented here), re-probes the real state after every change, and can
revert everything in one click. **You don't need the app** — [TWEAKS.md](TWEAKS.md)
lists every command to run yourself.
