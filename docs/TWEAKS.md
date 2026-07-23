# MacTweak — Tweak & Command Reference

Every optimization MacTweak can apply, with the **exact Terminal command** to
apply and revert it **by hand** — no app required. This is the plain-text twin
of [`index.html`](index.html).

> **How to use this by hand:** open **Terminal** (Applications → Utilities), paste
> the **Apply** line, press Return. To undo, paste the **Revert** line. MacTweak
> runs exactly these commands.

## Before you paste — three rules

1. **`sudo` lines** need an administrator password. Terminal asks once per session;
   your keystrokes stay invisible while typing (normal).
2. **`SIP off` lines** only take effect if **System Integrity Protection is
   disabled**. Most Macs keep SIP on — check with `csrutil status` and skip these
   if it says *enabled*. See [SAFETY.md](SAFETY.md).
3. Some UI tweaks **restart `Dock`/`Finder`** (a one-second blink) or need a
   **log out / log in** to fully apply.

Legend: 🔓 no sudo · 🔐 sudo · 🧱 SIP off required · ⚠️ advanced · ♻️ resets on reboot

---

## Summary

| Tweak | Category | Privilege | Notes |
|---|---|---|---|
| Disable Timer Coalescing | Performance | 🔐 | moderate |
| Disable App Nap | Performance | 🔓 | moderate |
| Raise GPU Memory Limit | Performance | 🔐 | ⚠️ ♻️ |
| Unthrottle Background I/O | Performance | 🔐 | moderate |
| Server Performance Mode | Performance | 🔐 | 🧱 ⚠️ reboot |
| Keep Low Power Mode Off | Power | 🔐 | safe |
| Disable Power Nap | Power | 🔐 | safe |
| Skip Hibernation Image | Power | 🔐 | ⚠️ |
| Instant Window Resizing | Snappiness | 🔓 | safe |
| Disable Window Animations | Snappiness | 🔓 | safe |
| Instant Dock Auto-Hide | Snappiness | 🔓 | restarts Dock |
| Turbo Key Repeat | Snappiness | 🔓 | re-login |
| Faster Mission Control | Snappiness | 🔓 | restarts Dock |
| Instant Fullscreen Menu Bar | Snappiness | 🔓 | restarts Dock |
| Disable Smooth Scrolling | Snappiness | 🔓 | moderate |
| Manual Window Tabbing | Snappiness | 🔓 | moderate |
| Reduce Transparency | Snappiness | 🔓 | safe |
| Reduce Motion | Snappiness | 🔓 | safe |
| Disable Finder Animations | Snappiness | 🔓 | restarts Finder |
| Fast Minimize Effect | Snappiness | 🔓 | restarts Dock |
| Disable App Launch Bounce | Snappiness | 🔓 | restarts Dock |
| Silence Crash Reporter | Privacy | 🔓 | safe |
| Disable Personalized Ads | Privacy | 🔓 | safe |
| Disable Diagnostics & Analytics | Privacy | 🔐 | 🧱 moderate |
| Harden Chromium & Chrome Telemetry | Privacy | 🔓 | browser restart |
| Disable Firefox Telemetry | Privacy | 🔓 | replaces user.js |
| Disable Media Analysis | Background Services | 🔓 | moderate |
| Disable Photo Analysis | Background Services | 🔓 | moderate |
| Disable Spotlight Indexing | Background Services | 🔐 | ⚠️ |
| Stop Bonjour Advertising | Network | 🔐 | moderate |
| Enlarge TCP Buffers | Network | 🔐 | ♻️ |
| Raise Socket Backlog | Network | 🔐 | ♻️ |
| Disable Siri Assistant | AI & Intelligence | 🔓 | moderate |
| Disable Proactive Intelligence | AI & Intelligence | 🔓 | moderate |
| Disable Siri Suggestions in Lookup | AI & Intelligence | 🔓 | safe |

---

## ⚡ Performance

### Disable Timer Coalescing — 🔐
Stops the kernel from batching timers. Lower latency, slightly more wakeups.
```bash
# Apply
sudo sysctl -w kern.timer.coalescing_enabled=0
# Revert
sudo sysctl -w kern.timer.coalescing_enabled=1
```

### Disable App Nap — 🔓
Keeps background apps running at full speed instead of being throttled.
```bash
# Apply
defaults write -g NSAppSleepDisabled -bool YES
# Revert
defaults delete -g NSAppSleepDisabled
```

### Raise GPU Memory Limit — 🔐 ⚠️ ♻️
Lets the GPU use up to ~75% of RAM (great for local ML / heavy graphics). The
command reads your total RAM and sets three-quarters of it. Resets on reboot.
```bash
# Apply
sudo sysctl -w iogpu.wired_limit_mb=$(( $(sysctl -n hw.memsize)/1024/1024*3/4 ))
# Revert
sudo sysctl -w iogpu.wired_limit_mb=0
```

### Unthrottle Background I/O — 🔐
Stops the kernel from throttling low-priority disk work, so background tasks finish faster.
```bash
# Apply
sudo sysctl -w debug.lowpri_throttle_enabled=0
# Revert
sudo sysctl -w debug.lowpri_throttle_enabled=1
```

### Server Performance Mode — 🔐 🧱 ⚠️ (reboot)
Biases the scheduler and memory for sustained throughput. Preserves your other
boot-args. Takes effect after a reboot. **Needs SIP disabled.**
```bash
# Apply
sudo nvram boot-args="serverperfmode=1 $(nvram boot-args 2>/dev/null | cut -f2-)"
# Revert
sudo nvram -d boot-args
```

---

## 🔋 Power

### Keep Low Power Mode Off — 🔐
Guarantees Low Power Mode stays disabled on battery and adapter.
```bash
# Apply
sudo pmset -a lowpowermode 0
# Revert
sudo pmset -a lowpowermode 1
```

### Disable Power Nap — 🔐
Stops background wake-ups for mail, backups and updates while asleep.
```bash
# Apply
sudo pmset -a powernap 0
# Revert
sudo pmset -a powernap 1
```

### Skip Hibernation Image — 🔐 ⚠️
Frees RAM-sized disk space and speeds sleep. Trade-off: you lose safe-sleep if the
battery fully dies.
```bash
# Apply
sudo pmset -a hibernatemode 0
# Revert
sudo pmset -a hibernatemode 3
```

---

## 🎬 Snappiness

All user-level, safe, reversible. Several relaunch Dock or Finder (a one-second blink).

### Instant Window Resizing — 🔓
```bash
# Apply
defaults write -g NSWindowResizeTime -float 0.001
# Revert
defaults delete -g NSWindowResizeTime
```

### Disable Window Animations — 🔓
```bash
# Apply
defaults write -g NSAutomaticWindowAnimationsEnabled -bool false
# Revert
defaults delete -g NSAutomaticWindowAnimationsEnabled
```

### Instant Dock Auto-Hide — 🔓 (restarts Dock)
```bash
# Apply
defaults write com.apple.dock autohide-delay -float 0 && defaults write com.apple.dock autohide-time-modifier -float 0.15 && killall Dock
# Revert
defaults delete com.apple.dock autohide-delay; defaults delete com.apple.dock autohide-time-modifier; killall Dock
```

### Turbo Key Repeat — 🔓 (log out to apply)
Fastest key repeat and shortest delay. Log out and back in to fully apply.
```bash
# Apply
defaults write -g KeyRepeat -int 2 && defaults write -g InitialKeyRepeat -int 15
# Revert
defaults delete -g KeyRepeat; defaults delete -g InitialKeyRepeat
```

### Faster Mission Control — 🔓 (restarts Dock)
```bash
# Apply
defaults write com.apple.dock expose-animation-duration -float 0 && killall Dock
# Revert
defaults delete com.apple.dock expose-animation-duration; killall Dock
```

### Instant Fullscreen Menu Bar — 🔓 (restarts Dock)
```bash
# Apply
defaults write com.apple.dock fullscreen-delay -float 0 && killall Dock
# Revert
defaults delete com.apple.dock fullscreen-delay; killall Dock
```

### Disable Smooth Scrolling — 🔓
```bash
# Apply
defaults write -g NSScrollAnimationEnabled -bool false
# Revert
defaults delete -g NSScrollAnimationEnabled
```

### Manual Window Tabbing — 🔓
Stops apps from auto-merging windows into tabs.
```bash
# Apply
defaults write -g AppleWindowTabbingMode -string manual
# Revert
defaults delete -g AppleWindowTabbingMode
```

### Reduce Transparency — 🔓
Cuts WindowServer GPU and RAM use by removing translucency and blur.
```bash
# Apply
defaults write com.apple.universalaccess reduceTransparency -bool true
# Revert
defaults delete com.apple.universalaccess reduceTransparency
```

### Reduce Motion — 🔓
```bash
# Apply
defaults write com.apple.universalaccess reduceMotion -bool true
# Revert
defaults delete com.apple.universalaccess reduceMotion
```

### Disable Finder Animations — 🔓 (restarts Finder)
```bash
# Apply
defaults write com.apple.finder DisableAllAnimations -bool true && killall Finder
# Revert
defaults delete com.apple.finder DisableAllAnimations; killall Finder
```

### Fast Minimize Effect — 🔓 (restarts Dock)
Uses the lightweight Scale effect instead of the Genie animation.
```bash
# Apply
defaults write com.apple.dock mineffect -string scale && killall Dock
# Revert
defaults delete com.apple.dock mineffect; killall Dock
```

### Disable App Launch Bounce — 🔓 (restarts Dock)
```bash
# Apply
defaults write com.apple.dock launchanim -bool false && killall Dock
# Revert
defaults delete com.apple.dock launchanim; killall Dock
```

---

## 🕵️ Privacy

Browser tweaks take effect on the next browser launch.

### Silence Crash Reporter — 🔓
```bash
# Apply
defaults write com.apple.CrashReporter DialogType none
# Revert
defaults delete com.apple.CrashReporter DialogType
```

### Disable Personalized Ads — 🔓 (works with SIP on)
```bash
# Apply
defaults write com.apple.AdLib allowApplePersonalizedAdvertising -bool false
# Revert
defaults write com.apple.AdLib allowApplePersonalizedAdvertising -bool true
```

### Disable Diagnostics & Analytics — 🔐 🧱
Stops the `analyticsd` telemetry daemon. Only possible with SIP disabled.
```bash
# Apply
sudo launchctl disable system/com.apple.analyticsd && sudo launchctl bootout system/com.apple.analyticsd
# Revert
sudo launchctl enable system/com.apple.analyticsd
```

### Harden Chromium & Chrome Telemetry — 🔓
Sets managed-policy flags across Chromium / Chrome / Brave / Edge to stop usage
stats, crash reports, URL data collection, search-keystroke and spell-check
phone-home. **Core Safe Browsing stays on.** Browsers show a "managed by your
organization" note. Takes effect on browser restart.
```bash
# Apply
for d in org.chromium.Chromium com.google.Chrome com.brave.Browser com.microsoft.Edge; do
  defaults write "$d" MetricsReportingEnabled -bool false
  defaults write "$d" UrlKeyedAnonymizedDataCollectionEnabled -bool false
  defaults write "$d" SafeBrowsingExtendedReportingEnabled -bool false
  defaults write "$d" SearchSuggestEnabled -bool false
  defaults write "$d" SpellCheckServiceEnabled -bool false
done

# Revert
for d in org.chromium.Chromium com.google.Chrome com.brave.Browser com.microsoft.Edge; do
  for k in MetricsReportingEnabled UrlKeyedAnonymizedDataCollectionEnabled SafeBrowsingExtendedReportingEnabled SearchSuggestEnabled SpellCheckServiceEnabled; do
    defaults delete "$d" "$k" 2>/dev/null
  done
done
```

### Disable Firefox Telemetry — 🔓 (replaces user.js)
Writes a managed `user.js` into every Firefox profile to turn off telemetry,
health-report upload, Shield studies, ping-centre and new-tab data collection.
Survives Firefox updates. **Replaces any existing `user.js`** in each profile.
Takes effect on Firefox restart.
```bash
# Apply
for p in "$HOME/Library/Application Support/Firefox/Profiles/"*/; do
  [ -d "$p" ] || continue
  printf '%s\n' \
    '// MacTweak privacy — Firefox telemetry off' \
    'user_pref("toolkit.telemetry.enabled", false);' \
    'user_pref("toolkit.telemetry.unified", false);' \
    'user_pref("toolkit.telemetry.archive.enabled", false);' \
    'user_pref("datareporting.healthreport.uploadEnabled", false);' \
    'user_pref("datareporting.policy.dataSubmissionEnabled", false);' \
    'user_pref("app.shield.optoutstudies.enabled", false);' \
    'user_pref("browser.ping-centre.telemetry", false);' \
    'user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);' \
    'user_pref("browser.newtabpage.activity-stream.telemetry", false);' \
    'user_pref("browser.discovery.enabled", false);' > "$p/user.js"
done

# Revert (only removes the file MacTweak wrote)
for p in "$HOME/Library/Application Support/Firefox/Profiles/"*/; do
  f="$p/user.js"
  [ -f "$f" ] && grep -q 'MacTweak privacy' "$f" && rm -f "$f"
done
```

> **Why not the app-bundle approach?** Firefox also reads a `policies.json` inside
> `Firefox.app`, but macOS **App Management / SIP** blocks writing into the bundle
> (`Operation not permitted`) even for root on a SIP-enabled Mac — and it gets wiped
> on every Firefox update. `user.js` is user-level and survives updates.

---

## 🧹 Background Services

### Disable Media Analysis — 🔓
Stops background scanning of photos/videos for objects and scenes (`mediaanalysisd`).
```bash
# Apply
launchctl disable gui/$(id -u)/com.apple.mediaanalysisd && launchctl bootout gui/$(id -u)/com.apple.mediaanalysisd
# Revert
launchctl enable gui/$(id -u)/com.apple.mediaanalysisd
```

### Disable Photo Analysis — 🔓
Stops face recognition and Memories generation in Photos (`photoanalysisd`).
```bash
# Apply
launchctl disable gui/$(id -u)/com.apple.photoanalysisd && launchctl bootout gui/$(id -u)/com.apple.photoanalysisd
# Revert
launchctl enable gui/$(id -u)/com.apple.photoanalysisd
```

### Disable Spotlight Indexing — 🔐 ⚠️
Turns off filesystem indexing on all volumes. Search still opens apps; it won't
find file contents.
```bash
# Apply
sudo mdutil -a -i off
# Revert
sudo mdutil -a -i on
```

---

## 🌐 Network

### Stop Bonjour Advertising — 🔐
Stops broadcasting services over Bonjour. AirDrop keeps working over AWDL.
```bash
# Apply
sudo defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool true && sudo killall -HUP mDNSResponder
# Revert
sudo defaults delete /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements && sudo killall -HUP mDNSResponder
```

### Enlarge TCP Buffers — 🔐 ♻️
Raises max TCP send/receive buffers to 16 MB for higher throughput on busy local servers.
```bash
# Apply
sudo sysctl -w net.inet.tcp.autorcvbufmax=16777216 net.inet.tcp.autosndbufmax=16777216
# Revert
sudo sysctl -w net.inet.tcp.autorcvbufmax=4194304 net.inet.tcp.autosndbufmax=4194304
```

### Raise Socket Backlog — 🔐 ♻️
Raises the max pending-connection queue (`somaxconn`) from 128 to 1024.
```bash
# Apply
sudo sysctl -w kern.ipc.somaxconn=1024
# Revert
sudo sysctl -w kern.ipc.somaxconn=128
```

---

## 🧠 AI & Intelligence

### Disable Siri Assistant — 🔓
Boots out the Siri assistant agent (`assistantd`) and hides its menu bar item.
```bash
# Apply
defaults write com.apple.Siri StatusMenuVisible -bool false && launchctl disable gui/$(id -u)/com.apple.assistantd && launchctl bootout gui/$(id -u)/com.apple.assistantd
# Revert
defaults delete com.apple.Siri StatusMenuVisible; launchctl enable gui/$(id -u)/com.apple.assistantd
```

### Disable Proactive Intelligence — 🔓
Stops `duetexpertd` — the on-device daemon behind Siri Suggestions and predicted actions.
```bash
# Apply
launchctl disable gui/$(id -u)/com.apple.duetexpertd && launchctl bootout gui/$(id -u)/com.apple.duetexpertd
# Revert
launchctl enable gui/$(id -u)/com.apple.duetexpertd
```

### Disable Siri Suggestions in Lookup — 🔓
```bash
# Apply
defaults write com.apple.lookup.shared LookupSuggestionsDisabled -bool true
# Revert
defaults delete com.apple.lookup.shared LookupSuggestionsDisabled
```

---

## 🛠️ One-shot Actions

Not toggles — run once, on demand. Nothing to revert.

| Action | Command |
|---|---|
| Purge Inactive Memory | `sudo purge` |
| Flush DNS Cache | `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder` |
| Restart Dock & Finder | `killall Dock Finder` |
| Restart Core Audio | `sudo killall coreaudiod` |
| Rebuild Spotlight Index | `sudo mdutil -E /` |

**Purge Bloat Daemons Now** (they may respawn — pair with the toggles above):
```bash
for p in mediaanalysisd photoanalysisd analyticsd spotlightknowledged knowledgeconstructiond geoanalyticsd; do
  sudo killall -TERM $p 2>/dev/null
done
```

---

## Verifying a change

Read the value with the same tool before and after:
```bash
defaults read -g NSWindowResizeTime            # snappiness
pmset -g | grep powernap                        # power
sysctl -n kern.ipc.somaxconn                    # network
mdutil -s /                                      # spotlight
launchctl print-disabled gui/$(id -u) | grep photoanalysisd
```
MacTweak does exactly this after every change — which is why it only marks a tweak
*Applied* when the system truly reports the new state.

See also: [SAFETY.md](SAFETY.md) · [FAQ.md](FAQ.md) · [ARCHITECTURE.md](ARCHITECTURE.md)
