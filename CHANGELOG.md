# Changelog

All notable changes to MacTweak. Dates are `YYYY-MM-DD`.

## [Unreleased]

### Added — Stop Accidental VoiceOver
- New **Snappiness** tweak disabling symbolic hotkey **59** (⌘F5, "Turn VoiceOver on or
  off") — the shortcut behind the recurring "Do you want to turn on VoiceOver?" dialog.
  Writes the whole hotkey entry in both directions so revert restores a working binding,
  and runs `activateSettings -u` so it applies without a re-login. VoiceOver itself is
  untouched. FAQ also documents the second trigger, triple-pressing Touch ID, which is a
  System Settings toggle with no `defaults` key.

### Added — Services page (see and stop background launchd jobs)
- **New Services pane** listing every non-Apple `launchd` job from
  `~/Library/LaunchAgents`, `/Library/LaunchAgents` and `/Library/LaunchDaemons`, with
  live state (running + pid, idle, disabled, last exit status) and **live CPU / memory
  per service** — the answer to "what is running behind my back and what does it cost?".
- **Two levels of off, both reversible:** **Stop** (`launchctl bootout` — until the next
  login) and **Disable** (`launchctl disable` + bootout — persists). Plus **Disable all**
  per group, and re-enable at any time. Every change goes to the audit trail.
- **Grouped by what it is**, which decides how freely it may be switched: developer
  services (Homebrew databases/servers/model runners), auto-updaters, app helpers,
  security & management, MacTweak's own.
- **Security/EDR agents are read-only** (Cortex XDR, CrowdStrike, Jamf, Defender…). On a
  managed Mac they're required by policy, and disabling one is both a compliance problem
  and a real loss of protection — listed for transparency, never switched.
- **Apple's daemons are not listed at all** — SIP-protected and load-bearing; the few
  worth changing already ship as reversible tweaks.
- **Uses `launchctl`, not `brew services`:** brew's wrapper is only a launchd front-end
  and breaks on new macOS releases (on macOS 26 it dies with "unknown or unsupported
  macOS version" before doing anything).
- **Detection is reconciled against launchd itself, not just the three standard
  directories** — the completeness guarantee. Since macOS 13 apps register background
  items with `SMAppService`, whose plist lives *inside the app bundle*, so no directory
  scan can see them. Anything launchd knows that the scan missed is added and tagged
  **App-registered**. On the dev machine this recovered **20 further services**: a
  running Teams agent, Docker's helper, OneDrive launchers, and ghost Homebrew
  registrations (`php@8.1`, `opensearch`, `postgresql-14`) whose plists were deleted but
  which launchd still lists. Four classes are deliberately excluded (Apple's, including
  unprefixed OS jobs that ship a plist in `/System/Library`; `application.*` running GUI
  apps; `NetworkExtension.*` providers) — 858 exclusions against 68 listed services.
- **Documented** in ARCHITECTURE.md ("detecting *every* background service": both
  discovery phases, every exclusion and its rationale, how to extend classification) and
  in FAQ.md with a copy-paste recipe to verify completeness on any machine.
- Also corrected the **stale CoreAudioWatchdog section** in ARCHITECTURE.md, which still
  documented the old 8% threshold and no cooldown.
- **Cost is measured over each service's whole process tree, not the one pid launchd
  reports** — which understated almost everything. `nginx` showed 0 MB and no ports
  because its master forks the workers that hold the memory and own the socket; the
  Homebrew `mysql` job is a `/bin/sh` wrapper (`mysqld_safe`) that owns nothing at all.
- **Listening ports per service** (`:3306`, `:9000`, `:80`) — the fastest way to
  recognise a service you forgot you were running, and shown in the disable
  confirmation so you know what's about to stop answering.
- **Handles services installed twice.** Homebrew often registers the same service as
  both a user agent and a root daemon; they're separate jobs and the *system* copy is
  usually the one running. State is read **per domain** (`launchctl print gui/<uid>` and
  `launchctl print system`, both readable without root) rather than from `launchctl
  list`, which only ever reports the caller's own domain and would have shown a system
  daemon its user agent's status. Duplicated names get an explicit warning, since
  disabling one copy leaves the other running.

### Added — Diagnosis knowledge captured in the docs
- **docs/FAQ.md** — "I cleaned my Mac and now it's hot. Did a tweak do that?": cleaning
  **defers** work rather than removing it, so the heat is the rebuild bill (Spotlight
  re-crawl, cache regeneration, a full Xcode build). Includes the audit-log query that
  rules out a tweak, and the measured episode (load average **23.75 on 8 cores**,
  self-resolving to **3.03**).
- **docs/FAQ.md** — "How do I tell which process is *really* using the CPU?": a single
  `top` frame overstates spikes (`duetexpertd` read 49.1% then accumulated **zero** CPU
  over 10 s), so measure `ps -o cputime=` deltas; `%CPU` is per-core not per-machine;
  compare load average to `hw.ncpu`.
- **docs/FAQ.md** — `coreaudiod` **busy vs. wedged** table (5–30% is normal DSP work,
  >100% is a spin), which is why the watchdog trips at 70%. Plus the app's own measured
  cost: ~7.5% of one core with the Dashboard open, ~0.1% with the window closed.
- **docs/SAFETY.md** — new "Cleanup & one-shot actions — reversible, but not free":
  these leave nothing switched on, so there's nothing to revert, but they bill the
  machine afterwards in CPU/heat/battery. Per-action delayed-cost table and the advice
  not to chase the resulting heat by changing settings.
- **docs/TWEAKS.md** — the cooling section now notes that "subtract work" applies to
  *when* you run maintenance, not just which tweaks you apply.
- Verified all cross-document anchors resolve against GitHub's real slug rules
  (which keep the leading hyphen from a stripped emoji, `## 🌐 Network` → `#-network`,
  and emit a double hyphen for ` — `).

### Fixed — Docker row reported a size that could never drop
- **`Docker.raw` was measured with `ls -lh`, which reads the sparse file's *logical*
  ceiling** — a number that by design never shrinks. It showed **60G** on a machine
  where only **1.5G** was actually allocated, so pruning appeared to do nothing and
  the "reclaimable" headline was inflated by ~58 GB of space that was never occupied.
  Now measured with `du` (blocks actually on disk), so a prune visibly lands.
- **Prune no longer reports a false success.** `docker system prune … 2>/dev/null;
  true` masked the exit code, so with Docker Desktop not running the row still said
  "done." while freeing nothing. The real exit code and daemon error now surface.
- **Cleanup rows now report what was freed** instead of a bare "done." — the tools
  that know say so (`Total reclaimed space: 1.2GB`, `This operation has freed…`).
  Matched by keyword, not "last line of output", since `npm cache clean` ends on a
  `--force` warning and a failing `brew` ends on a Ruby backtrace frame.

### Fixed — Core Audio Watchdog restart loop
- **The watchdog flapped.** Confirmed from its own log: 8 restarts in ~7 minutes at
  a dead-regular 45 s cadence (exactly its minimum re-trip period). `killall
  coreaudiod` makes launchd relaunch it immediately, the stuck HAL plugin loads
  back into the fresh process, and it pegs again — so the watchdog re-tripped
  forever, blipping audio each time and never touching the cause.
- Added a **5-minute cooldown** between restarts and a **3-attempt cap**. After
  three failures it gives up, keeps watching, and names the actual fix (quit the
  app that installed the plugin in `/Library/Audio/Plug-Ins/HAL/`, usually Teams).
  A sustained calm stretch (~2 min) clears the streak so a later wedge still acts.
- **Threshold raised 8% → 70%.** 8% was below what `coreaudiod` legitimately uses
  during a call with echo cancellation or spatial audio, so the watchdog could kill
  audio mid-call; a genuinely wedged stream spins a whole core or more (156%
  observed).
- **Fixed a dead baseline reset:** `trip()` cleared the previous sample, but
  `tick()`'s `defer` immediately wrote it back, so a pid change burned a tick
  instead of rebaselining — the reason the loop period was 45 s rather than 30 s.
- Watchdog restarts, give-ups and recoveries now appear in the audit log.

### Added — Cooling-aware tuning guidance (fanless vs. actively cooled)
- **docs/TWEAKS.md** gains a section explaining that a fan changes *what the
  bottleneck is*, with a per-tweak table for fanless (Air) vs. actively cooled
  (Pro / desktop). Four tweaks flip: **Unthrottle Background I/O** (skip on an
  Air), **Server Performance Mode** (cooled desktops only — never an Air), the
  **background-daemon disables** (bigger real payoff on an Air, because
  background heat derates the foreground too), and **Keep Low Power Mode Off**
  (nuanced for long sustained work on a fanless machine). Process Priority also
  differs: `renice` can't raise a *thermal* ceiling, so **Yield** beats **Boost**
  on an Air.
- **docs/FAQ.md** gains "Should I tune a MacBook Air differently from a Pro?" and
  "How do I tell whether my CPU is actually being throttled?".
- **Fixed an inconsistency this exposed:** the wizard auto-recommended
  *Unthrottle Background I/O* to anyone choosing **Performance**, including on
  fanless Macs where the docs now (correctly) say to skip it. Added a
  `needsActiveCooling` tag, applied to that tweak and Server Performance Mode,
  which the wizard skips on a passively-cooled machine.

### Added — Thermal & CPU speed check
- **Thermal card** on the Dashboard answers "am I getting full performance, or am
  I being throttled?" — reading macOS's own thermal-pressure level
  (`ProcessInfo.thermalState`), which is free, needs no admin, and updates live.
- **Check speed** samples real per-cluster frequencies via `powermetrics` (admin,
  on demand) and shows current vs. **maximum** MHz per cluster with a bar. The
  hardware maximum is derived from the DVFS residency histogram, since
  `hw.cpufrequency` doesn't exist on Apple Silicon. Handles multi-cluster chips
  (an M3 Pro/Max reports P0 and P1 separately).
- States plainly that **a frequency below maximum is normally just idle, not
  throttling** — only the pressure level means the ceiling was actually lowered.
- On fanless Macs (Airs), adds a note that they shed heat by slowing down, so
  sustained loads throttle where brief bursts don't.

### Added — Renice any process
- **Busiest processes** table on the Process Priority page: every running process
  sorted by CPU (not just the six curated targets), with per-row **Boost** (−5),
  **Yield** (+10) and **Reset** (0). Lets you renice whatever `top` would have
  shown you — `coreaudiod`, Electron helpers, a runaway Python — instead of only
  the predefined set.
- **Fixed:** `setNice` verified the result by searching the known-target list, so
  renicing anything outside it always reported failure even when it worked. It
  now re-reads the specific pid.

### Added — Audit trail
- **Every system change is logged** to macOS's unified log under a dedicated
  `audit` category (`subsystem == "com.tanguy.MacTweak"`), readable with
  `log show`/`log stream` or in Console.app, and mirrored to
  `~/Library/Logs/MacTweak/MacTweak.log` as `[CHANGE]` lines.
- Covers tweak apply/revert (with before → intended → *actual* state, so
  `result=ok` means **verified**, not just "exited 0"), presets and revert-all
  batches, one-shot actions, `renice` changes, apply-at-login LaunchAgents,
  disk-cleanup deletions, the ad-block weekly updater, and admin unlock/lock.
- Entries are greppable `key=value` pairs and deliberately public — only
  non-sensitive identifiers (keys, states, exit codes, pids), never raw commands.
- Irreversible deletions log each path **before** acting, so the record survives
  a pass that dies partway through.

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
