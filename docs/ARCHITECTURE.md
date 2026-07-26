# MacTweak — Architecture

How the app is built, for anyone reading or extending the code.

## At a glance

- **Language / UI:** Swift 6, SwiftUI, Swift Charts. Targets **macOS 15+**.
- **Shape:** a **menu-bar app** — `MenuBarExtra(.window)` + a full `Window` scene.
  `LSUIElement` is set so there is **no Dock icon**; the app runs as an accessory.
- **Distribution:** **not sandboxed**, **ad-hoc (locally) signed**. It has to drive
  `pmset`, `mdutil`, `launchctl`, `defaults`, `sysctl`, `nvram` and escalate through
  the native macOS password prompt — none of which is possible inside the App Sandbox.
- **State:** a small set of `@MainActor ObservableObject`s owned by `AppModel`.

## Layout

```
Sources/MacTweak/
  App/        MacTweakApp (scenes), AppModel (+ wizard), Theme (design system)
  Core/       CommandRunner, TweakEngine, SystemInfo, CoreAudioWatchdog, Log
  Models/     Tweak, TweakCategory, TweakCatalog (+ iconOverrides), Presets
  Metrics/    SystemMetrics (Mach sampling), Benchmark (+ BenchmarkHistory), ThermalMonitor
  Views/      Dashboard, TweakList/Row, Benchmark, Actions, Sidebar, Menu,
              ScanSheet, MainWindow, Components (HeroHeader, RingGauge, gauges)
  Onboarding/ OnboardingView
Scripts/      build.sh, make_icon.swift
docs/         index.html, TWEAKS.md, ARCHITECTURE.md, SAFETY.md, FAQ.md
```

## Data model — the tweak catalog is the source of truth

Everything is data-driven. `TweakCatalog.all` is an array of `Tweak` values; adding
a tweak = adding one entry (see [CONTRIBUTING.md](../CONTRIBUTING.md)).

```swift
struct Tweak {
    let key, title, summary: String
    let category: TweakCategory
    let privilege: Privilege            // .user | .admin
    let risk: Risk                       // .safe | .moderate | .advanced
    let sipRequired: Bool
    let applyCommand, revertCommand, statusCommand: String
    let appliedWhenOutputContains: String   // substring test on statusCommand stdout
    let tags: [TweakTag]
    let recommended: Bool
    var privilegeRunner: (String) -> CommandResult { privilege == .admin ? .admin : .user }
}
```

`SystemAction` is the same idea for **one-shot** commands (purge, flush DNS, restart
Core Audio…) — no persistent on/off state.

### Tweak state & probing

```swift
enum TweakState { case applied, notApplied, unknown, unavailable }
```

`TweakEngine.probe(_:)` decides state by **running the real `statusCommand`** and
checking whether stdout contains `appliedWhenOutputContains`:

```swift
static func probe(_ t: Tweak) -> TweakState {
    if t.sipRequired && SystemInfo.sipEnabled { return .unavailable }   // SIP-blocked → greyed out
    let r = CommandRunner.user(t.statusCommand)
    if r.output.isEmpty { return .notApplied }
    return r.output.localizedCaseInsensitiveContains(t.appliedWhenOutputContains) ? .applied : .notApplied
}
```

The app **never trusts an exit code** — after every apply/revert it re-probes, so a
tweak only shows *Applied* if the system actually changed.

## TweakEngine — the brain (`@MainActor ObservableObject`)

- `state: [String: TweakState]` — per-tweak, `@Published`.
- `refreshAll(reporting:)` — probes the **whole catalog concurrently** via
  `withTaskGroup`, updating a progress bar as each real probe returns; then diffs
  against the previous state to build a `ScanSummary` of what changed.
- `set(_:to:)` / `toggle(_:)` — apply or revert one tweak, then re-probe.
- `runBatch(_:to:)`, `applyRecommended()`, `revertAll()`, `apply(preset:)`,
  `apply(keys:)` — bulk operations used by presets and the wizard.
- `run(_ action:)` — one-shot actions.
- `unlockAdmin()` / `lockAdmin()` — passwordless-admin management (below).
- `writeEmergencyRevertScript()` — writes `~/Documents/MacTweak_Revert.sh`, a
  standalone script that reverts every tweak from Terminal if the app can't.
- `reactivate()` — after the macOS auth dialog closes, brings the app + main window
  back to the front (a menu-bar app loses focus and *looks* like it crashed
  otherwise). Called centrally from `CommandRunner.adminPrompt`.

## CommandRunner — two escalation lanes

```swift
CommandRunner.user(_:)   // /bin/zsh -c <command>          (no prompt)
CommandRunner.admin(_:)  // root, via one of two backends
```

`admin()` picks a backend based on whether passwordless admin is unlocked:

- **`adminPrompt`** — `osascript … do shell script "…" with administrator privileges`.
  The native password dialog; no helper tool, no stored password, no deprecated
  Authorization API. The command is **base64-wrapped** before it reaches AppleScript
  so arbitrary quoting/piping survives.
- **`adminNoPrompt`** — `sudo -n /bin/zsh -c …`. Silent; requires the sudoers rule.

### Passwordless admin (authenticate once)

`enablePasswordlessAdmin()` prompts **once** and installs
`/etc/sudoers.d/mactweak` (root-owned `0440`, validated with `visudo -c`):

```
<user> ALL=(root) NOPASSWD: /bin/zsh
```

After that, every admin tweak runs via `sudo -n` with no prompt. **Lock** removes
the file. Security note: this grants your user passwordless root via `/bin/zsh` — a
real convenience/safety trade fine for a personal machine. See [SAFETY.md](SAFETY.md).

### The `run()` plumbing — why not `waitUntilExit()`

Commands run through a single `run(executable:arguments:)`:

- Waits via **`terminationHandler` + `DispatchSemaphore`**, *not* `Process.waitUntilExit()`.
  `waitUntilExit()` services the calling thread's run loop while waiting, so a call
  made during SwiftUI view evaluation re-enters the framework mid-update and triggers
  `AttributeGraph: cycle detected` / a `dispatch_once` deadlock. A plain blocking wait
  has identical semantics without the re-entrancy.
- Drains **stdout and stderr concurrently** (stderr on a background queue with a
  barrier). Reading one pipe fully before the other deadlocks any command that fills
  the ~64 KB pipe buffer of the un-read stream.
- All blocking work is dispatched off the main actor (`await Task.detached { … }.value`).

## SystemMetrics — live CPU/RAM (`@MainActor ObservableObject`)

- Reads straight from the **Mach kernel** — `host_statistics(HOST_CPU_LOAD_INFO)` for
  CPU ticks, `host_statistics64(HOST_VM_INFO64)` for memory — no shelling out.
- CPU is **EMA-smoothed** so the menu-bar panel and the window converge on the same
  figure instead of catching different instantaneous spikes.
- The Mach **host port** and **page size** are cached in statics (calling
  `mach_host_self()` every tick leaks a send right).
- **Ref-counted sampling:** views call `retain()` in `.onAppear` and `release()` in
  `.onDisappear`; the 1 Hz timer only runs while a gauge is on screen. This was the
  app's entire idle CPU footprint — off-screen it costs nothing.
- No per-tick implicit `.animation(...)`: animating a chart/ring every second was
  continuous SwiftUI recompositing (it once put idle CPU at ~32%). Removing it +
  ref-counting brought idle to ~0%.

## ServicesManager — detecting *every* background service

The hard requirement for the Services page is completeness: a machine that isn't the
developer's must not quietly hide a service. Scanning the well-known directories alone
does **not** achieve that, so discovery runs in two phases.

### Phase 1 — the three standard directories

| Directory | launchd domain | Needs admin to change |
|---|---|---|
| `~/Library/LaunchAgents` | `gui/<uid>` | no |
| `/Library/LaunchAgents` | `gui/<uid>` | no |
| `/Library/LaunchDaemons` | `system` | **yes** (runs as root) |

Each `.plist` is parsed with `PropertyListSerialization` (handles binary *and* XML), and
the **`Label` key inside the file wins over the filename** — they're conventionally the
same but nothing enforces it, and a mismatch would otherwise create a row whose
`launchctl` target doesn't exist.

`/System/Library/Launch{Agents,Daemons}` is never scanned: that's the OS.

### Phase 2 — reconcile against launchd itself (the completeness guarantee)

Directory scanning is *conventional*, not *authoritative*. Since macOS 13 the standard
way for an app to install a background item is **`SMAppService`**, which registers a
plist from **inside the app bundle** (`Foo.app/Contents/Library/LaunchAgents/…`). Those
jobs exist, run, and are invisible to any directory scan. `launchctl print` marks them:

```
path = (submitted by smd.90609)      # smd = the Service Management daemon
```

So MacTweak asks launchd what it actually knows, and adds anything the directory scan
missed. On the development machine this recovered **20 further services** the first
phase never saw — a running Teams agent, Docker's helper, OneDrive launchers, plus
several *ghost* Homebrew registrations (`homebrew.mxcl.php@8.1`, `opensearch`,
`postgresql-14`) whose plists are long gone but which launchd still lists.

Those rows are flagged **App-registered**. They can be stopped and disabled normally
(`bootout`/`disable` address the *label*, not a file), but re-enabling only clears the
flag — there's no plist path to `bootstrap`, so the owning app re-registers it at the
next login.

**This is why a custom service you invented is still detected**: whatever installed it,
if launchd is running it, it appears.

### What is deliberately excluded, and why

`isReportable(_:)` drops four classes. Each exclusion is a deliberate claim, not an
oversight:

| Excluded | Why |
|---|---|
| `com.apple.*` | Apple's own. SIP-protected and load-bearing |
| Any label with a plist in `/System/Library/Launch*` | **Also Apple's, but unprefixed** — `com.openssh.ssh-agent`, `com.vix.cron`, `org.cups.cupsd`. Caught by looking for the file, not by trusting the name |
| `application.<bundle-id>.<n>.<n>` | A *running GUI app* launchd tracks for the session (Firefox, Zed, MacTweak itself). Not a service; vanishes when the app quits |
| `NetworkExtension.*` | VPN tunnels and content filters, managed by the NetworkExtension framework and System Settings — `launchctl enable/disable` is not the right lever |

On the development machine that's 858 exclusions against 68 listed services.

### Verifying completeness on any machine

To prove nothing is hidden, diff launchd's inventory against what's on disk:

```bash
# What launchd knows (both domains), minus Apple's:
{ launchctl print gui/$(id -u); launchctl print system; } 2>/dev/null \
  | sed -n '/services = {/,/^	}/p' | awk 'NF>=3 {print $NF}' \
  | grep -v '^com\.apple\.' | sort -u > /tmp/launchd.txt

# What a directory scan alone would find:
ls ~/Library/LaunchAgents /Library/LaunchAgents /Library/LaunchDaemons 2>/dev/null \
  | grep '\.plist$' | sed 's/\.plist$//' | sort -u > /tmp/ondisk.txt

comm -13 /tmp/ondisk.txt /tmp/launchd.txt     # the gap phase 2 closes
```

Then trace any single label to its origin:

```bash
launchctl print gui/$(id -u)/<label> | head -5   # or system/<label>; no root needed
```

### Classification

`classify(label:program:)` buckets a job by label and executable path, **most specific
first**, so a security agent can never fall through into a controllable group:

1. **security** — `paloaltonetworks`/`cortex`, `crowdstrike`, `sentinelone`, `jamf`,
   `microsoft.defender`, `kandji`, `intune`… → listed **read-only**
2. **mactweak** → our own agents
3. **updater** — `update`, `keystone`, `autoupdate`, `sparkle`
4. **developer** — `homebrew.mxcl.*`, or any program under `/opt/homebrew/`, or a known
   server name (`mysql`, `postgres`, `redis`, `nginx`, `ollama`…)
5. **vendor** — `docker`, `teamviewer`, `adobe`, `zoom`…
6. **other** — everything unmatched

An unrecognised custom service is **still listed and still controllable**; it just lands
in **Other**. Misclassification never hides a service — it only changes which heading it
sits under. To teach it a new name, add a substring to the relevant array in
`Sources/MacTweak/Core/ServicesManager.swift`; adding to the `security` list is how you
make something *protected* from MacTweak's own controls.

### Cost measurement

CPU, memory, process count and listening ports are summed over each job's **whole
process tree**, not the single pid launchd reports — otherwise `nginx` reads 0 MB with
no ports (its master forks the workers that hold the memory and own the socket) and
Homebrew's `mysql` job reads 0 MB (it's a `/bin/sh` wrapper, `mysqld_safe`). Two passes
total — one `ps -Ao pid=,ppid=,%cpu=,rss=` and one `lsof -nP -iTCP -sTCP:LISTEN` —
regardless of service count.

### Not covered by this page

These start things at boot but aren't launchd jobs, so they're out of scope:

```bash
crontab -l                                  # cron jobs
sudo ls /etc/periodic/*/                    # periodic scripts
docker ps -a --filter 'status=running' \
  --format '{{.Names}}: {{.Image}}'         # containers with restart policies
ls /Library/StartupItems 2>/dev/null        # deprecated, occasionally still present
```
Login items that aren't launchd jobs live in **System Settings → General → Login Items
& Extensions**.

## BenchmarkEngine — measuring, and keeping the measurements

Four micro-benchmarks (single-core, multi-core, memory `memcpy` bandwidth, disk
write+read), each run in a detached task so the UI stays live. Every workload feeds a
`BenchSink` static, without which the optimizer deletes the timed loop entirely.

**One scoring function.** `Bench.score(singleCore:multiCore:memory:disk:)` holds the
weights, and both the in-session `BenchmarkResult` and the persisted `BenchmarkRecord`
call it. Two copies of those weights would put today's run and last month's on different
scales — a phantom cliff in the timeline with no cause in the hardware.

### History

- Appended to `~/Library/Application Support/MacTweak/benchmark-history.json` —
  pretty-printed, `sortedKeys`, ISO-8601 dates, so it reads and greps by hand like the
  audit trail. Written atomically, off the main actor, capped at **400 records**.
- A corrupt or half-written file decodes to an **empty history**, never a crash. Losing
  the trend is recoverable; a crash loop on a file you can't see isn't.
- Every run also lands in the audit trail as `benchmark.run`.

### The daily schedule

Opt-in, off by default — a benchmark saturates every core for several seconds, and doing
that unasked is rude. Persisted in `UserDefaults` (`benchmark.daily`, `.dailyHour`,
`.lastAttemptDay`); the hour defaults to **12**.

- **Polled every 5 minutes, not fired by a one-shot timer at the due time.** A laptop is
  asleep at some point most days, and a sleeping Mac silently swallows a scheduled fire.
  Polling notices the missed slot on the next wake. The first tick is one interval after
  launch, which doubles as a grace period so opening the app doesn't peg all cores while
  login items are still settling.
- **Deferred while the Mac is warm or busy** — `ProcessInfo.thermalState != .nominal`, or
  `getloadavg` 1-minute load above 60% of core count. A benchmark measures whatever the
  machine has *left*, so running it mid-build records the build. It retries each tick.
- **Skipped after a 4-hour grace window.** A "noon" score recorded at 11pm on a warm Mac
  isn't comparable to the rest of the series; a gap in the chart is more honest than a
  bad point. `lastAttemptDay` marks the day as handled for a run *or* a skip, so neither
  repeats. The skip is audited (`benchmark.skipped`).
- **Scheduled runs are recorded to history only.** They stay out of the
  Baseline / After tweaks session, which they would otherwise silently redefine — set a
  baseline in the morning and noon's run becomes what your tweaks get measured against.

## CoreAudioWatchdog

A third-party virtual-audio HAL driver (e.g. Microsoft Teams') can wedge a stream and
peg `coreaudiod` — the driver runs **inside** `coreaudiod`, so the cost bills there.

- Samples `coreaudiod` CPU every **15 s** via `ps -o cputime=` (a cputime *delta*).
- Trips after **2 sustained ticks** over a **70%** threshold (~30 s). The bar is high on
  purpose: `coreaudiod` legitimately sustains 5–30% during a call with echo cancellation
  or spatial audio, and a wedged stream spins a whole core or more (156% observed). A
  lower bar restarts audio mid-call, which is worse than the problem.
- On trip, restarts `coreaudiod` via the `restart-coreaudio` action — but only
  **silently** if passwordless admin is unlocked (else it just reports "unlock admin
  to auto-restart"). Persisted on/off in `UserDefaults` (`watchdog.coreaudio`).
- **A restart is not assumed to work.** launchd relaunches `coreaudiod` immediately and
  the offending HAL plugin loads back into the fresh process, so a naive watchdog
  re-trips every ~45 s forever. Hence a **5-minute cooldown** and a **3-attempt cap**,
  after which it gives up, keeps watching, and names the plugin to remove. ~2 minutes of
  calm clears the streak.

## Log

- Writes to the **unified log** (`subsystem == "com.tanguy.MacTweak"`, query with
  `log show --predicate …`) **and** a plain file at
  `~/Library/Logs/MacTweak/MacTweak.log`.
- Instruments the escalation path (`admin start/done`, action results, unlock/lock)
  so failures aren't a blind spot.
- Installs **async-signal-safe crash handlers**: the file descriptor is force-opened
  at install time and each `signal()` handler writes a single preallocated byte
  buffer (no malloc, no `String`, no lazy init) before re-raising — an OS `SIGKILL`
  leaves no `.ips`, so this is the only record.

## Theme — the design system

- Single accent from the requested OKLCH colors: `accent = #F54900`
  (`oklch(64.6% 0.222 41.116)`), `accentDeep = #E7000E` (`oklch(57.7% 0.245 27.325)`).
- `accentGradient` — a vertical top→bottom orange→red used on ring gauges, every
  `GlyphTile`, gradient buttons and pills.
- `GradientButtonStyle` (`.gradient` / `.gradientOutline`) is the app-wide button look.
- The blue focus ring is disabled app-wide (`.focusEffectDisabled()` on both scenes).
- Fibonacci spacing scale (8·13·21·34·55·89) and apple.com neutral greys.

## Presets

One-tap bundles that only include **real, available** tweaks (SIP-blocked / advanced
excluded): **Balanced · Performance · Snappy UI · Battery · Privacy · AI / Server**.

## Build

`Scripts/build.sh` compiles, bundles into `build/MacTweak.app`, generates the
`Info.plist` (stamping `CFBundleVersion` with the git commit), builds the `.icns`,
ad-hoc signs with `MacTweak.entitlements`, and launches. Flags: `--no-launch`,
`--debug`, `--help`. See [CONTRIBUTING.md](../CONTRIBUTING.md).
