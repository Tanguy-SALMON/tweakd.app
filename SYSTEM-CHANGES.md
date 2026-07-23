# System Changes Log

Every macOS setting that was modified on this Mac while building & testing MacTweak,
with the exact command used, what it does, and its current status.

- **When:** 2026-07-22, during UI testing (the app's guided-setup wizard auto-applied
  its user-level tweaks).
- **Current status:** ✅ **All reverted to stock and verified.** Nothing below is
  currently applied.
- **Scope:** Only **user-level** settings were changed. No `sudo`/admin command ever
  ran — no password prompt was approved — so power, Spotlight, kernel, and network
  settings were **never touched**.

---

## Settings that were modified, then reverted

Each was applied by the app, then reverted with `defaults delete` / `launchctl enable`.
"Original value" = the key did not exist (macOS default behavior); it is unset again now.

| # | Domain / key | Applied value | Revert command | Now |
|---|--------------|---------------|----------------|-----|
| 1 | `-g NSWindowResizeTime` | `0.001` | `defaults delete -g NSWindowResizeTime` | ✅ unset |
| 2 | `-g NSAutomaticWindowAnimationsEnabled` | `false` (0) | `defaults delete -g NSAutomaticWindowAnimationsEnabled` | ✅ unset |
| 3 | `-g NSAppSleepDisabled` | `YES` (1) | `defaults delete -g NSAppSleepDisabled` | ✅ unset |
| 4 | `com.apple.dock autohide-delay` | `0` | `defaults delete com.apple.dock autohide-delay` | ✅ unset |
| 5 | `com.apple.dock autohide-time-modifier` | `0.15` | `defaults delete com.apple.dock autohide-time-modifier` | ✅ unset |
| 6 | `-g KeyRepeat` | `2` | `defaults delete -g KeyRepeat` | ✅ unset |
| 7 | `-g InitialKeyRepeat` | `15` | `defaults delete -g InitialKeyRepeat` | ✅ unset |
| 8 | `com.apple.CrashReporter DialogType` | `none` | `defaults delete com.apple.CrashReporter DialogType` | ✅ unset |
| 9 | `com.apple.lookup.shared LookupSuggestionsDisabled` | `true` (1) | `defaults delete com.apple.lookup.shared LookupSuggestionsDisabled` | ✅ unset |
| 10 | `com.apple.Siri StatusMenuVisible` | `false` (0) | `defaults delete com.apple.Siri StatusMenuVisible` | ✅ unset |
| 11 | launchd agent `gui/$UID/com.apple.photoanalysisd` | disabled | `launchctl enable gui/$UID/com.apple.photoanalysisd` | ✅ enabled |
| 12 | launchd agent `gui/$UID/com.apple.mediaanalysisd` | disabled | `launchctl enable gui/$UID/com.apple.mediaanalysisd` | ✅ enabled |

### What each one does

1. **NSWindowResizeTime** — window resize animation duration (made near-instant).
2. **NSAutomaticWindowAnimationsEnabled** — open/close window animations (turned off).
3. **NSAppSleepDisabled** — App Nap throttling of background apps (disabled it).
4. **dock autohide-delay** — delay before the Dock auto-shows (set to 0).
5. **dock autohide-time-modifier** — Dock show/hide animation speed (sped up).
6. **KeyRepeat** — key repeat rate (fastest).
7. **InitialKeyRepeat** — delay before repeat starts (shortest).
8. **CrashReporter DialogType** — the "app quit unexpectedly" dialog (silenced).
9. **LookupSuggestionsDisabled** — Siri-powered suggestions in Lookup (disabled).
10. **Siri StatusMenuVisible** — Siri menu-bar item visibility (hidden).
11. **photoanalysisd** — background Photos face recognition / Memories (stopped).
12. **mediaanalysisd** — background media scanning for objects/scenes (stopped).

> **Side effect:** applying #4/#5 ran `killall Dock`, and reverting ran it again — the
> Dock restarted twice (a brief flash). No persistent effect.

---

## Settings that were **NOT** modified

These are in the app's catalog but were never applied (they need admin, and no
password prompt was ever approved). They remain at their original values:

- `pmset -a lowpowermode` (was already `0`)
- `pmset -a powernap`
- `pmset -a hibernatemode`
- `sysctl kern.timer.coalescing_enabled`
- `mdutil -a -i` (Spotlight indexing — still **enabled**)
- `com.apple.mDNSResponder NoMulticastAdvertisements`
- `com.apple.analyticsd` (blocked by SIP anyway)
- `com.apple.assistantd` (Siri agent — was not booted out)
- `net.inet.tcp.autorcvbufmax` / `autosndbufmax` (Enlarge TCP Buffers — default 4 MB, resets on reboot)
- `kern.ipc.somaxconn` (Raise Socket Backlog — default 128, resets on reboot)
- `serverperfmode` boot-arg (Server Performance Mode — needs SIP off + reboot; unavailable while SIP on)
- `killall coreaudiod` (Restart Core Audio quick action — one-shot, self-respawns)

---

## App's own preferences (not a system setting)

MacTweak stored its own state in the `com.tanguy.MacTweak` UserDefaults domain
(`didOnboard`, `tweak.order`, `tweak.favorites`). This was also cleared with
`defaults delete com.tanguy.MacTweak` so you get a clean first run.

---

## How to re-verify at any time

```bash
for k in NSWindowResizeTime NSAutomaticWindowAnimationsEnabled NSAppSleepDisabled KeyRepeat InitialKeyRepeat; do
  printf "%s: " "$k"; defaults read -g "$k" 2>/dev/null || echo "(unset ✓)"
done
defaults read com.apple.dock autohide-delay 2>/dev/null || echo "dock delay (unset ✓)"
defaults read com.apple.CrashReporter DialogType 2>/dev/null || echo "crashreporter (unset ✓)"
defaults read com.apple.lookup.shared LookupSuggestionsDisabled 2>/dev/null || echo "lookup (unset ✓)"
defaults read com.apple.Siri StatusMenuVisible 2>/dev/null || echo "siri (unset ✓)"
launchctl print-disabled gui/$(id -u) | grep -E "photoanalysisd|mediaanalysisd" || echo "analysis daemons (enabled ✓)"
```
