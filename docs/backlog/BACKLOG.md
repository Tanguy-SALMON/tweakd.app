# Backlog

Ideas consolidated from old PRP_2–PRP_5 planning docs (removed after this audit — see git
history if the original write-ups are needed). All items below are now implemented; kept
for history/context on the "rejected" sysctls.

## From PRP_2 (beta perf tweaks) — done

- TouchBar disable toggle (`launchctl unload` the TouchBar agent) — `touchbar-disable`
- Notification Center widget background-refresh toggle — `notification-center-refresh-off`
- `isBeta` flag on `Tweak` + beta-warning-dialog UI component (confirm-before-enable for
  risky tweaks) — `Models/Tweak.swift`, `Views/Components/BetaWarningDialog.swift`
- Dictionary/Lookup background-indexing toggle — `dictionary-indexing-off`

Rejected, not backlog: WindowServer memory-compression sysctl, GPU-priority sysctl,
IOThrottle sysctl, Metal-validation tweaks — these reference sysctls that don't actually
exist on macOS.

## From PRP_4 (AI/dev workload tuning) — done

- Docker Desktop resource presets — scoped down to a read-only `docker info` action plus a
  jump-to-Settings shortcut (`docker-resources-info`, `docker-open-settings`); editing
  Docker's resource-limit JSON directly was rejected as too version-fragile
- Ollama env tuning (`OLLAMA_NUM_GPU`, `OLLAMA_KEEP_ALIVE`) as a tweak/preset — `ollama-tuning`
- `serverperfmode` boot-arg toggle (raises `kern.maxproc`, `somaxconn`, etc.) — already existed
- TCP buffer tuning tweak (`net.inet.tcp.autorcvbufmax`/`autosndbufmax`) — already existed
- Named presets for local-LLM/dev workflows ("AI Development", "Local LLM Server",
  "Containerised Web") — added to `Presets.swift` alongside the generic `server` preset

## From PRP_5 (security + process priority) — done

Mostly already implemented (`TweakCatalog.swift` .security category, `PriorityManager.swift`,
`ProcessPriorityView.swift`). Remaining gaps, now closed:

- Menubar quick-action submenu for one-click security/network presets — `MenuView.swift`
  disclosure group over `hardened`/`lowlatency` presets
- Guided-setup: replace the single "harden security" toggle with a fuller
  Security-Hardened / Balanced / Performance-First choice — `AppModel.SecurityPosture`,
  `OnboardingView.swift`

## Note on PRP_3 (Core Audio Repair)

Not carried into this backlog — its goal (fix pegged `coreaudiod`) is already solved by a
different, better design: `Core/CoreAudioWatchdog.swift`, an opt-in background watchdog
that auto-restarts `coreaudiod` when it spikes.

## Always-on / server mode — shipped, needs verification

Three tweaks added to the Power category, all scoped to `-c` (power adapter) rather than
`-a`, so battery behaviour is untouched: `never-sleep-on-power`, `never-disksleep-on-power`,
`disable-standby-on-power`.

Outstanding:

- **Not yet applied on real hardware.** The read-side is verified — each `statusCommand`
  was run and parses the AC block correctly — but `pmset -c …` needs root, so the write
  side and the re-probe round trip are untested. Apply once and confirm the row flips to
  Applied rather than "System reported no change."
- **Revert values are assumed defaults**, matching what this Mac reported (`sleep 1`,
  `disksleep 10`, `standby 1`). A Mac configured differently would be reverted to these
  rather than to what it had. Same convention as the existing `pmset` tweaks, but worth
  revisiting if anyone reports a surprise.
- **`docs/TWEAKS.md` has no entries for the three** — the table around line 135 and the
  detail sections around line 244 both need rows adding.
- **Wake-on-network (`womp`) and `tcpkeepalive` were deliberately left out**: both already
  read `1` on this machine, so a tweak would have shipped permanently "Applied" and done
  nothing. Add only if a Mac is found where they default off.
- **`systemsetup -setrestartpowerfailure` was considered and dropped** — it errors with
  "Not supported on this machine" on Apple Silicon notebooks, so it would be a dead toggle.

## Power button — undecided

`defaults write com.apple.loginwindow PowerButtonSleepsSystem -bool no` stops a stray press
of the Touch ID key sleeping the Mac. Already set to `0` on the dev machine, applied by hand.

Not added: the key reads and writes fine, but whether **macOS 26 still honours it** can only
be settled by physically pressing the power button. There are credible reports of it being
ignored on recent macOS, and shipping it unverified would be exactly the dead toggle the
catalog rule forbids. Test, then add or discard.

## From `BACKLOG.mg` (user requests, Aug 2026) — done

Free-form notes dropped at the repo root; folded in here and the file removed.

- **GPU usage diagram, like the CPU one ("like in MACtop")** — `GPUCard` +
  `GPUMonitor`, shipped in 0.8.x
- **A very visible one-tap button next to "~9.5 GB reclaimable right now."** —
  `DiskCleanupManager.cleanAll()` / the `Clean Up Now` banner button, 0.9.0. Scoped
  to `risk == .safe && !destructive`: Trash, Docker prune and iOS backups are
  deliberately excluded, because a one-tap sweep must never be the thing that
  deletes something you wanted.
- **"Nominal is a result" — make the thermal state legible, explain the levels** —
  the four-rung `pressureScale` ladder with per-level meanings, 0.9.0
- **Live Performance/Efficiency core speeds, refreshing every second** —
  `CommandRunner.streamAdmin` + `ThermalMonitor` live mode, 0.9.0. Needs the
  passwordless-sudo lane: `osascript … with administrator privileges` buffers
  stdout until exit, so it cannot stream.
- **"Do you know the temperature?"** — no. Apple Silicon publishes no die
  temperature to unprivileged apps, so the card says so outright rather than
  leaving the dashed `Serious`/`Critical` rules unexplained.
