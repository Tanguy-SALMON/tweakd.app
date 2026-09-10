# Changelog

All notable changes to Tweakd. Dates are `YYYY-MM-DD`.

## [Unreleased]

## [0.10.3] — 2026-09-10

### Fixed — a bad URL gave you a blank page on tweakd.app

`wrangler.worker.toml` sets `not_found_handling = "404-page"`, but there was no
`web/404.html` to serve — so every mistyped or dead link returned **404 with an
empty body**. The Pages mirror had the opposite bug: it answered unmatched paths
with **200 and the homepage**, a soft-404 that tells search engines every URL on
the site exists.

`web/404.html` fixes both. It reuses `privacy.html`'s shell verbatim — same
palette, same dark-mode handling — so it doesn't look like it belongs to a
different site, and it links back to the front page and the command reference.

## [0.10.2] — 2026-09-10

### Fixed — tweakd.app was never being deployed

The apex is a Workers **custom domain** on the service `still-pond-7677`, not a
Cloudflare Pages custom domain. `wrangler pages deploy` therefore never touched
it, and it had been serving the 2026-07-30 build — v0.4.0, with the dead
`href="#"` download button and the removed "View source" link — the entire time
pages.dev was current.

- `worker/index.js` serves tweakd.app: `/api/download` from R2, everything else
  from the assets binding.
- `wrangler.worker.toml` targets that service.
- `shared/r2-download.js` holds the R2 lookup once, so the Pages Function and
  the Worker cannot drift apart. `functions/api/download.js` is now two
  re-exports.
- `release-website.sh` deploys **both** front doors and fails preflight if
  either config is missing. Deploying one and not the other is what caused this.

### Changed — every Download link downloads

The header button and the nav item both pointed at `#get`, scrolling to the
bottom of the page instead of fetching anything. All three now point at
`/api/download`.

## [0.10.1] — 2026-09-10

### Documented — the download machinery 0.10.0 added

`README.md` and `docs/ARCHITECTURE.md` still described a repo with no
`functions/`, no `wrangler.toml`, no `dist/`, and a `scripts/` holding two files
instead of four. Both layouts now match what's on disk, and the README gains a
short "Publishing a release" section: `release-download.sh` then
`release-website.sh`, with the reason the first one re-reads
`X-Tweakd-Version` from the live endpoint rather than trusting the upload.

## [0.10.0] — 2026-09-10

### Added — the Download button actually downloads

It had been `href="#"` since the site went up, under a note reading "Example
buttons — point these at your release `.dmg`". There was no `.dmg` to point at,
because the build stopped at `app/build/tweakd.app`.

Three pieces, modelled on how the MyD1/SQLAgent sites do it:

- **`scripts/package-dmg.sh`** wraps the bundle in `dist/Tweakd-<version>.dmg`
  with an `/Applications` symlink, and refuses to package if the built bundle's
  `CFBundleShortVersionString` disagrees with `app/VERSION`.
- **`functions/api/download.js`**, a Pages Function bound to the R2 bucket
  `tweakd-downloads`, lists the bucket and streams the highest-versioned object.
  Deriving "current" from the bucket means there is no pointer to go stale.
- **`scripts/release-download.sh`** packages, uploads, then HEADs the live
  endpoint and compares `X-Tweakd-Version` against `app/VERSION` — an upload can
  succeed while the Function is broken.

`wrangler.toml` now exists at the repo root for the R2 binding, and
`release-website.sh` deploys with no directory argument so that config applies;
deploying `web/` explicitly would ship the same files with no bindings and every
download would 500.

The `.dmg` is not committed — `dist/` is gitignored.

## [0.9.5] — 2026-09-10

### Fixed — the website's AI section was missing a tweak, and the nav a third of the page

A per-section audit of the live page against `TweakCatalog.swift` found **Tune
Ollama for GPU & Keep-Alive** filed under *Process Priority*. Its `category:` is
`.ai`, and the AI & Intelligence section listed 3 of its 4 tweaks. Moved.

Every section now matches the catalog exactly: Performance 5, Power 8, Snappiness
14, Privacy 5, Background Services 4, Security & Network 11 (split across the
page's `#network` and `#secnet`), AI & Intelligence 4 — **51**. Process Priority
holds the 8 `PriorityManager` targets, and One-shot Actions the 9 real actions.

The nav bar linked 11 of the page's 14 sections: **Power**, **Background
Services** and **AI** had no entry, so three whole categories were reachable only
by scrolling.

## [0.9.4] — 2026-09-10

A full audit of every Markdown file and of the website's command reference
against `TweakCatalog.swift`. No behaviour change in the app.

### Fixed — "Disable Diagnostics & Analytics" was documented as needing SIP off

It doesn't, and hasn't for a while. The catalog moved that tweak from
`launchctl disable system/com.apple.analyticsd` to
`defaults write /Library/Preferences/com.apple.SubmitDiagInfo`, which plain admin
can do with SIP **on**. `SAFETY.md`, `FAQ.md`, `TWEAKS.md` and the website all
still described the launchctl version and badged it 🧱. `serverperfmode` is the
only `sipRequired: true` tweak, so the "two SIP-off tweaks" framing is gone.

### Fixed — commands that would not have done what they said

- **Privacy DNS** and **Disable IPv6** were documented (and shown on the site) as
  Wi-Fi-only. The catalog loops over every network service.
- The **ad-block revert** stripped only `# tweakd-adblock-*`. The real command
  also strips legacy `# MacTweak-adblock-*`, so following the doc would have left
  the old block in `/etc/hosts`.
- **Bonjour**, **Media/Photo Analysis**, **Proactive Intelligence** and **Siri**
  chained `launchctl bootout` with `&&` on the website. Under SIP that returns
  150 and aborts the line.
- **Raise mDNSResponder** used `pgrep mDNSResponder`; `PriorityManager` uses
  `pgrep -f`.

### Added — the docs and the site now cover the whole catalog

`docs/TWEAKS.md` was missing 7 tweaks and 3 actions. The website was missing 9
tweaks — including the entire **Block Ads & Trackers** hosts-file tweak — and 3
actions, while claiming to list "every tweak and the exact command". Both are
complete: **51 tweaks, 9 actions**.

### Fixed — the app was described as smaller than it is

`README.md` and `docs/ARCHITECTURE.md` omitted nine `Core/` files and eight
`Views/`, didn't mention the network throughput tiles, called the dashboard
meters "ring gauges" (there is no `RingGauge`), and showed a `probe(_:)` snippet
with an early `return .unavailable` the real code doesn't do. The site's feature
card claimed "48 reversible tweaks" and listed categories that don't exist.

### Documented — two limits nobody had written down

Live thermal sampling stops itself after 900 samples (~15 min), and the Core
Audio watchdog trips only after **two consecutive** hot samples, not one.

### Changed — the sweep is called "Clean Up Now"

That's what the button says; the docs called it "Clean All".

## [0.9.3] — 2026-09-10

Documentation and website catch-up. No behaviour change — the app binary differs
from 0.9.2 only in its version string.

### Documented — the features shipped in 0.8.x/0.9.x that nothing described

- **GPU gauge** — `README.md`, `docs/ARCHITECTURE.md` and `docs/TOOLS.md` now
  cover it, including the `ioreg`/`AGXAccelerator` one-liner it is read from
  (`Device Utilization %`, `In use system memory`) and why that beats
  `powermetrics --samplers gpu_power`: no root required.
- **Disk Cleanup's one-tap sweep** — `docs/TOOLS.md` gains a "Clean Up Now" section
  stating the inclusion rule (`risk == .safe && !destructive`), why Trash, Docker
  prune and iOS backups are excluded, and why the sweep total is smaller than the
  headline reclaimable figure. `docs/SAFETY.md` records the `cleanup.sweep` audit
  entry.
- **Thermal card** — the one-line level list in `docs/TOOLS.md` became a table of
  what Nominal/Fair/Serious/Critical each mean, plus live mode (1 Hz, needs admin
  unlocked, stops on leaving the pane) and the "no die temperature" note.
- **`CommandRunner.streamAdmin` / `StreamHandle`** — `docs/ARCHITECTURE.md` now
  explains the constraint that forced it: `osascript … with administrator
  privileges` buffers stdout until exit, so only the passwordless `sudo -n` lane
  can stream. It also records why `stop()` closes the read end of the pipe —
  terminating `sudo` does not reap its child, but SIGPIPE on the child's next
  write does.

### Fixed — the website advertised the wrong numbers

`web/index.html` claimed **v0.8.0** and "48 tweaks + 6 actions". The catalog has
**51 tweaks and 9 actions**, and the version pill is now 0.9.3. The page also
gains cards for the thermal ladder, the Disk Cleanup sweep and the GPU gauge.

### Corrected — `docs/ARCHITECTURE.md`'s layout tree

The `docs/` line listed five of eleven files, and the `web/` line said the page is
"published at tweakd.app". It is deployed to the Cloudflare Pages project
`tweakd-app`; `tweakd.app` is not currently one of that project's domains.

## [0.9.2] — 2026-09-10

### Fixed — documented daemon commands reported failure when they had worked

`docs/TWEAKS.md` chained the background-service disables with `&&`:

```bash
launchctl disable gui/$(id -u)/com.apple.mediaanalysisd && launchctl bootout ...
```

Under SIP, `bootout` returns `150: Operation not permitted`, so the whole line
exits non-zero even though the `disable` — the half that actually persists — had
succeeded. The commands now use `;` and a trailing `true`, matching what
`TweakCatalog.swift` has always done.

### Documented — what `disable` does and does not do

`docs/SAFETY.md` gains a section on the four background-service tweaks
(`mediaanalysisd`, `photoanalysisd`, `assistantd`, `duetexpertd`): `disable`
stops launchd from *starting* a daemon but macOS can still spin it up on demand,
so the process being alive afterwards is expected. It also records that a macOS
update can silently drop the override — after 26.6.2, two of the four were no
longer in `launchctl print-disabled`.

## [0.9.1] — 2026-08-13

### Fixed — the thermal scale used colours from outside the palette

The four rungs were drawn in system `.green`, `.yellow`, `.orange` and `.red`,
none of which appear anywhere else in the app.

The ramp is now built from colours already in `Theme` and already validated for
both light and dark: `gpuAccent` (teal) for the calm end, `accent` at half then
full strength, and `accentDeep` for critical. The live-sampling dot and the
alarming verdict icon were the same mistake and follow the same rule.

## [0.9.0] — 2026-08-13

### Added — one button that cleans the safe caches

Disk Cleanup led with "~9.5 GB reclaimable right now" and then made you clear
thirteen rows one at a time.

"Clean Up Now" sits next to that headline and sweeps every **safe, regenerable**
row in one pass. It deliberately does *not* touch the Trash, Docker's images and
volumes, or your device backups — a one-tap button must never be the thing that
deletes something irreplaceable, so those keep their own individual buttons.

The banner quotes the sweep's own total separately from the headline, because
the headline includes rows the button leaves alone, and the confirmation names
every item it is about to clear rather than asking for blanket consent.

### Added — live CPU cluster speeds

Performance and Efficiency core frequencies now refresh every second while
"Go live" is on, instead of being a single frozen sample.

`powermetrics` needs root and takes ~300 ms, so polling it once a second would
mean a new root process every second. Instead one sampler is started and its
output is streamed and parsed block by block. That requires *streaming* root,
which only the passwordless sudoers rule provides — the authorization dialog
buffers output until the command exits, so live mode says it needs Admin Access
unlocked rather than failing silently.

The sampler is bounded (15 min) and stopped when the pane closes; closing our
end of the pipe is what actually kills it, since terminating `sudo` doesn't
reap its child.

Each block's maximum MHz is carried forward across samples: the residency
histogram only lists the steps a cluster actually visited that second, so an
idle cluster reports a low "max" and the percentage would jump around.

### Added — the thermal pressure scale is explained

"Nominal" was a verdict with nothing to measure it against, and the dashed rules
on the trend strip were labelled with states the UI never defined.

All four levels — Nominal, Fair, Serious, Critical — are now shown as a scale
with the current rung lit and what it means for you spelled out underneath.

Also answered in the UI: there is no temperature reading, because Apple Silicon
doesn't publish a die temperature to apps. The pressure level is the signal
macOS itself acts on when it decides to slow down.

### Changed — the main window opens at 80% of the screen

Sized against the screen's *visible* frame rather than its full frame, so the
window never opens partly under the menu bar or the Dock, and clamped to the
existing 880×620 minimum for small displays.

`.defaultSize` can't do this alone — it only applies when AppKit has no saved
frame to restore, so on any install that had run before, the window came back at
whatever size it was last left at.

### Changed — the brand reads "Tweakd" in the UI

The app said `tweakd` in the sidebar, menu bar and window title while the website
already said **Tweakd**.

`Brand.name` couldn't simply be capitalised: it builds the support directory, log
file, revert script and sudoers rule, all of which already exist on disk under the
lowercase name. Renaming it would orphan them — the sudoers rule being the one
that matters, since it grants passwordless root and the UI would report admin as
locked while the rule stayed behind.

So `Brand.displayName` now covers everything the user reads and `Brand.name` keeps
the paths. `build.sh` makes the same split: `CFBundleName` and
`CFBundleDisplayName` are "Tweakd", while `CFBundleExecutable` and the `.app`
filename stay lowercase.

### Removed — the duplicated window title

`NavigationSplitView` draws the window title in the toolbar strip above the detail
pane, right beside a sidebar header already showing the brand and version. The
title is dropped from the toolbar only; the scene keeps it, so the Window menu and
Mission Control still identify the window.

## [0.8.0] — 2026-07-31

### Added — selectable text everywhere it's worth copying

Text in a SwiftUI view isn't selectable by default, so a process name, a service
label, a tweak description or an error message could be read but never copied —
awkward when the natural next step is to paste it into a search.

`.textSelection(.enabled)` now applies across every pane, scoped **narrowly** — to
individual `Text` views or small text-only groups, never to a whole page. A
page-level scope turns the entire pane into one selection region and swallows
clicks on the `Button`s, `Toggle`s, `Slider`s and `Picker`s inside it.

Where a header and the card beneath it read as one block (Process Priority,
Services), they share a single scope so a drag selects continuously across both.
The Refresh/Rescan button in those headers is restructured as a sibling outside
that scope rather than a descendant, so it stays a button.

### Removed — drag-to-reorder in the tweaks list

The `List`'s `.onMove` drag gesture competed with text selection on the same rows.
Reordering went, and `TweakEngine.move(in:from:to:)` with it; the persisted
`order` array still drives display order.

### Changed — the app now shows a Dock icon

`LSUIElement` is `false` in the generated `Info.plist`, so tweakd appears in the
Dock **and** the menu bar instead of menu-bar-only.

### Changed — the website capitalises the brand as "Tweakd"

0.7.0 made everything user-visible lowercase `tweakd`. The site now reads
**Tweakd** in prose, titles and nav. This is a website-only change — the app's
`Brand.name`, and every identifier derived from it, stays lowercase.

Identifiers deliberately left lowercase on the site too: the `tweakd.app` domain,
`app.tweakd.priority.*` LaunchAgent labels, and the `// tweakd privacy` marker —
that last one is matched byte-for-byte by the Firefox revert command, so
capitalising it would strand the file it's meant to delete.

### Added — Privacy Policy and Terms of Service pages

`web/privacy.html` and `web/terms.html`, styled to match the site and linked from
every footer alongside the GitHub repo. The footer also drops its
"verified against macOS output formats" line (internal jargon) and the author's
name from the copyright.

## [0.7.0] — 2026-07-30

### Changed — renamed MacTweak → tweakd (`tweakd.app`)

Everything user-visible is now lowercase **tweakd**. The Swift module stays `Tweakd`
(Swift convention, invisible at runtime) and the bundle identifier is **`app.tweakd`**,
the reverse-DNS of the domain.

| | Was | Is |
|---|---|---|
| Bundle | `MacTweak.app` | `tweakd.app` |
| Bundle ID / log subsystem | `com.tanguy.MacTweak` | `app.tweakd` |
| Support dir | `…/Application Support/MacTweak/` | `…/Application Support/tweakd/` |
| Log file | `…/Logs/MacTweak/MacTweak.log` | `…/Logs/tweakd/tweakd.log` |
| sudoers rule | `/etc/sudoers.d/mactweak` | `/etc/sudoers.d/tweakd` |
| LaunchAgents | `com.mactweak.*` | `app.tweakd.*` |
| Revert script | `~/Documents/MacTweak_Revert.sh` | `~/Documents/tweakd_Revert.sh` |
| `/etc/hosts` markers | `# MacTweak-adblock-*` | `# tweakd-adblock-*` |
| Firefox `user.js` marker | `// MacTweak privacy` | `// tweakd privacy` |
| SPM target / sources | `MacTweak` · `Sources/MacTweak/` | `Tweakd` · `Sources/Tweakd/` |

### Added — migration, because a rename orphans real state

A rename changes the bundle identifier, and macOS keys preferences on it. Shipping the
rename alone would make the app look **brand new** on an existing install — onboarding
again, no favorites, no tweak order, no window position, no benchmark history, audit log
from zero — with all of it intact in directories nothing reads any more.

`LegacyMigration` runs once, before the first preference read or log write:

- **Preferences** copied from `com.tanguy.MacTweak` into `app.tweakd`, never overwriting
  a value the new domain already has. The old domain is **left in place** — deleting a
  user's only copy of their settings to save a few KB is a bad trade if anything's wrong.
- **Application Support** and **Logs** directories moved, with `MacTweak.log` renamed so
  the audit trail stays continuous rather than restarting.
- **Ad-block LaunchAgent re-registered** under the new label. Not a file rename: launchd
  keys the loaded job on the `Label` *inside* the plist, and the old helper script had the
  old `/etc/hosts` markers baked in. The old job is booted out and deleted, so the Mac
  doesn't end up running two weekly rebuilds fighting over the same block.
- File moves never delete what they couldn't move, and the migration is idempotent.

### Fixed — three artifacts that a blind rename would have stranded

These live in root-owned or third-party files, where migrating would mean a password
prompt at launch. Instead the **new name is written and both are recognised**:

- **`/etc/sudoers.d/mactweak`** — **Lock Admin** now removes every path the app has ever
  written. Missing this would have been the serious one: Lock would report success while
  the old drop-in kept granting passwordless root indefinitely. Detection was already
  path-independent (it tests `sudo -n`, not the file), and **Unlock** now clears the old
  rule as it writes the new one.
- **`/etc/hosts` ad-block markers** — status and revert match either marker pair. On the
  dev Mac that's **93,156 blocked domains** fenced by the old markers: matching only the
  new ones would have reported the tweak **Off** while it was on, and revert would have
  left every entry behind with nothing in the UI able to remove them.
- **Firefox `user.js` marker** — status and revert match either, so a `user.js` written
  before the rename is still detected and still removable. Status now emits a normalized
  `APPLIED` instead of the marker text, since `appliedWhenOutputContains` takes one string.

Priority LaunchAgents scan both prefixes, and the emergency revert script cleans up both.

## [0.6.0] — 2026-07-26

**Theme: seeing what your Mac is actually doing.** Where earlier versions were a
catalog of toggles, this one adds the instruments — every background service and
what it costs, disk usage broken down and reclaimable, thermal pressure vs. real
clock speed, benchmark scores kept over time, and an audit trail of every change
with its *verified* result. Plus the manuals for all of it.

### Added — Documentation for the tools, with Terminal equivalents
- **New [docs/SERVICES.md](docs/SERVICES.md)** — the background-services guide: launchd
  domains and why picking the wrong one is the #1 reason a command "does nothing", a
  step-by-step **tutorial** (find → verify → stop → check → make permanent → undo), the
  full `launchctl` cookbook (list · find failing · inspect · measure cost · stop ·
  disable · **restart**), where plists live including app-registered `SMAppService`
  items, what not to touch, and a **troubleshooting section for each `launchctl` error**.
  - Documents the **exit-code table** (`78 = EX_CONFIG` — almost always a port already
    held by a duplicate root daemon, which is exactly what's happening on the dev Mac).
  - All output shown is real, captured from `launchctl print`, not invented.
- **New [docs/TOOLS.md](docs/TOOLS.md)** — Terminal equivalents for every pane that
  isn't a tweak: Dashboard metrics and Clear RAM, Thermal & CPU speed, **all 13 Disk
  Cleanup rows** (measure + clear command each), Process Priority, Benchmark history
  (JSON schema and how to plot it without the app), the Core Audio watchdog, and the
  audit trail.
- **`Block Ads & Trackers (hosts file)` was shipping undocumented** — now in TWEAKS.md
  with its apply/revert/check commands, the marker mechanism, its caveats, and how to
  remove the weekly auto-update LaunchAgent by hand.
- Corrected two claims while verifying against the live machine: `pmset -g therm` reports
  nothing useful on Apple Silicon (so "no warning" ≠ "not throttled" — `powermetrics
  --samplers thermal` is the real source), and service listings need to filter
  `application.*` / `NetworkExtension.*`, which are launchd bookkeeping for open apps
  rather than background services.

### Added — Benchmark history & daily runs
- **Results are now saved.** Every run is appended to
  `~/Library/Application Support/tweakd/benchmark-history.json` (pretty-printed JSON,
  ISO-8601 dates, capped at 400 records) instead of vanishing when the app quits.
- **Timeline card** — a line chart of the overall score over time plus the last 8 runs
  with the change against the run before. Scheduled runs are drawn as dots, manual ones
  as diamonds, since they aren't measured under the same conditions.
- **Daily Benchmark** — opt-in automatic run at a chosen hour (defaults to **12:00**).
  Off by default: a benchmark saturates every core for a few seconds.
  - **Polled every 5 minutes rather than fired by a one-shot timer**, because a sleeping
    laptop silently swallows a scheduled fire — polling catches up after a wake.
  - **Postponed while the Mac is warm or busy** (thermal pressure above nominal, or 1-min
    load above 60% of core count). A benchmark measures what the machine has *left*, so
    running it mid-build records the build, not the Mac.
  - **Skips the day after a 4-hour grace window** rather than recording a late, warm,
    non-comparable score. Both the run and the skip land in the audit trail.
- Scheduled runs are recorded to history **only** — they deliberately stay out of the
  Baseline / After tweaks comparison, which they would otherwise silently redefine.
- The scoring weights now live in one place (`Bench.score`), shared by the in-session
  result and the persisted record, so today's run and last month's are on the same scale.
- **Clear** still clears only the current A/B session; history has its own
  **Clear history** action.

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
  security & management, tweakd's own.
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
  `audit` category (`subsystem == "app.tweakd"`), readable with
  `log show`/`log stream` or in Console.app, and mirrored to
  `~/Library/Logs/tweakd/tweakd.log` as `[CHANGE]` lines.
- Covers tweak apply/revert (with before → intended → *actual* state, so
  `result=ok` means **verified**, not just "exited 0"), presets and revert-all
  batches, one-shot actions, `renice` changes, apply-at-login LaunchAgents,
  disk-cleanup deletions, the ad-block weekly updater, and admin unlock/lock.
- Entries are greppable `key=value` pairs and deliberately public — only
  non-sensitive identifiers (keys, states, exit codes, pids), never raw commands.
- Irreversible deletions log each path **before** acting, so the record survives
  a pass that dies partway through.

## [0.5.0] — 2026-07-23

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
  tweakd's priority LaunchAgents.

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
- **Diagnostic logging** — unified log + `~/Library/Logs/tweakd/tweakd.log` with
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
- Initial tweakd: menu-bar system-tweak tool — data-driven catalog, user/admin
  escalation via the native macOS dialog, reversible tweaks, presets, guided setup,
  benchmarks.

---

Versions correspond to the `VERSION` file, stamped into `CFBundleShortVersionString`
at build time; `CFBundleVersion` additionally carries the short git commit.
