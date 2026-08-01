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
