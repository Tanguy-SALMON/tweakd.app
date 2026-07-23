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
  Metrics/    SystemMetrics (Mach sampling), Benchmark
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

## CoreAudioWatchdog

A third-party virtual-audio HAL driver (e.g. Microsoft Teams') can wedge a stream and
peg `coreaudiod` — the driver runs **inside** `coreaudiod`, so the cost bills there.

- Samples `coreaudiod` CPU every **15 s** via `ps -o cputime=` (a cputime *delta*).
- Trips after **2 sustained ticks** over an **8%** threshold (~30 s).
- On trip, restarts `coreaudiod` via the `restart-coreaudio` action — but only
  **silently** if passwordless admin is unlocked (else it just reports "unlock admin
  to auto-restart"). Persisted on/off in `UserDefaults` (`watchdog.coreaudio`).

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
