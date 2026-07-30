# Backlog

Unimplemented ideas consolidated from old PRP_2–PRP_5 planning docs (removed after this
audit — see git history if the original write-ups are needed).

## From PRP_2 (beta perf tweaks)

- TouchBar disable toggle (`launchctl unload` the TouchBar agent)
- Notification Center widget background-refresh toggle
- `isBeta` flag on `Tweak` + beta-warning-dialog UI component (confirm-before-enable for
  risky tweaks)
- Dictionary/Lookup background-indexing toggle

Rejected, not backlog: WindowServer memory-compression sysctl, GPU-priority sysctl,
IOThrottle sysctl, Metal-validation tweaks — these reference sysctls that don't actually
exist on macOS.

## From PRP_4 (AI/dev workload tuning)

- Docker Desktop resource presets (CPU/RAM/swap/disk allocation guidance or automation)
- Ollama env tuning (`OLLAMA_NUM_GPU`, `OLLAMA_KEEP_ALIVE`) as a tweak/preset
- `serverperfmode` boot-arg toggle (raises `kern.maxproc`, `somaxconn`, etc.)
- TCP buffer tuning tweak (`net.inet.tcp.autorcvbufmax`/`autosndbufmax`)
- Named presets for local-LLM/dev workflows ("AI Development", "Local LLM Server",
  "Containerised Web") — current `server` preset in `Presets.swift` is a generic analog

## From PRP_5 (security + process priority)

Mostly already implemented (`TweakCatalog.swift` .security category, `PriorityManager.swift`,
`ProcessPriorityView.swift`). Remaining gaps:

- Menubar quick-action submenu for one-click security/network presets
- Guided-setup: replace the single "harden security" toggle with a fuller
  Security-Hardened / Balanced / Performance-First choice

## Note on PRP_3 (Core Audio Repair)

Not carried into this backlog — its goal (fix pegged `coreaudiod`) is already solved by a
different, better design: `Core/CoreAudioWatchdog.swift`, an opt-in background watchdog
that auto-restarts `coreaudiod` when it spikes.
