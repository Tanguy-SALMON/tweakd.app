# Changelog

All notable changes to MacTweak. Dates are `YYYY-MM-DD`.

## [Unreleased]

### Added — Security & Process Priority module (PRP_5)
- **Security & Network** category with seven new tweaks: Enable Application
  Firewall, Enable Stealth Mode, Block Auto-Allow Signed Apps, Use Privacy DNS
  (Cloudflare), Disable IPv6, Enable TCP Window Scaling, and Raise Max File
  Descriptors. (Bonjour, TCP buffers, and socket backlog moved into this category.)
- **Process Priority** pane: a live table of network/UI processes (mDNSResponder,
  Firefox, Chrome, Docker, sshd, Media Analysis) with a per-process `renice`
  slider, one-tap Boost/Yield, an "Apply at login" LaunchAgent, a per-card
  "Show command" disclosure, and an emergency "Reset all to default".
- **Presets:** Hardened Security and Low-Latency Net.
- **Guided Setup** gained three questions (network services, security-first,
  low-latency) that steer the recommended set.
- **Menu-bar quick actions:** Quick Security, Low-Latency Network, Reset Priorities.
- Emergency revert script now also resets renice priorities and removes
  MacTweak's priority LaunchAgents.

### Fixed (code review, max-effort pass)
- **Emergency revert script** now single-quotes admin revert commands, so reverts
  containing `"` or `$(…)` reach root's shell intact instead of being mangled or run
  as the user.
- **`fast-key-repeat` status** no longer false-positives on stock `KeyRepeat` values
  that merely contain a `2` (12, 20, 120) — it emits an explicit `APPLIED` marker.
- **`chromium-telemetry-off` status** now checks all four browsers (Edge was missing
  from the read while apply/revert wrote it).
- **Crash log signal handler** is now async-signal-safe (fd force-opened at install;
  writes a single preallocated buffer — no malloc/String/lazy-init).
- **`CommandRunner`** drains stdout and stderr concurrently (no deadlock on large
  stderr); admin auth reactivation is centralized so the primary apply path recovers
  focus too.
- **`SystemMetrics`** caches the Mach host port and page size (was leaking a
  `mach_host_self()` send right every sample).
- Ring gauge guards against a `NaN` value reaching `.trim`.
- Log timestamp `%03d` fed a correctly-sized `Int32`.

### Added
- **Documentation set:** `docs/index.html` (web docs with copy-to-clipboard for every
  command), `docs/TWEAKS.md`, `docs/ARCHITECTURE.md`, `docs/SAFETY.md`, `docs/FAQ.md`,
  `CONTRIBUTING.md`, `CHANGELOG.md`.

## [0.4.0] — 2026-07-23

### Added
- **App-wide orange→red gradient** on buttons and background icons, using the exact
  OKLCH colors `oklch(64.6% 0.222 41.116)` → `#F54900` and
  `oklch(57.7% 0.245 27.325)` → `#E7000E` (vertical top→bottom).
- **Re-scan modal** — a progress sheet that re-probes every tweak and summarizes what
  changed since the last scan.
- **Core Audio Watchdog** — auto-restarts a runaway `coreaudiod` (e.g. a stuck
  third-party HAL driver) after ~30 s over threshold.
- **Clear RAM** button on the Dashboard's Memory ring (purges inactive pages).
- **Browser-privacy tweaks** in the Privacy tab: Disable Personalized Ads, Harden
  Chromium & Chrome Telemetry (Chromium/Chrome/Brave/Edge), Disable Firefox Telemetry
  (per-profile `user.js`).
- **Diagnostic logging** — unified log + `~/Library/Logs/MacTweak/MacTweak.log` with
  crash/signal handlers.
- Disabled the blue focus ring app-wide.

### Changed
- Ref-counted metric sampling (only runs while a gauge is on screen) and removed
  per-second implicit animations — idle CPU dropped from ~32% to ~0%.

### Fixed
- Admin actions no longer *appear* to crash — the app reactivates and raises its
  window after the auth dialog (a menu-bar app otherwise drops behind other windows).

## [0.3.0] — 2026-07-23
- Integrated the real, safe subset of the PRP proposals: Enlarge TCP Buffers, Raise
  Socket Backlog, Restart Core Audio, Server Performance Mode fix (preserves boot-args),
  and an **AI / Server** preset. Rejected fictional/dangerous items.

## [0.2.0] — 2026-07-23
- Redesigned UI; passwordless admin (one-time sudoers unlock); live CPU/RAM metrics;
  more tweaks. Simplified hot paths (dedup, caching, parallel probing). README refresh.

## [0.1.0] — 2026-07-22
- Initial MacTweak: menu-bar system-tweak tool — data-driven catalog, user/admin
  escalation via the native macOS dialog, reversible tweaks, presets, guided setup,
  benchmarks.

---

Versions correspond to the `VERSION` file, stamped into `CFBundleShortVersionString`
at build time; `CFBundleVersion` additionally carries the short git commit.
