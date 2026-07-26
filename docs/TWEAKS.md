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

## Fanless vs. actively cooled — yes, this changes what you should apply

A fan is not a detail. It changes *what the bottleneck is*, and four tweaks below
should be applied differently because of it.

**Which machine do you have?**

| | Fanless (passively cooled) | Actively cooled (has fans) |
|---|---|---|
| Models | MacBook Air (all Apple Silicon), 12″ MacBook | MacBook Pro, Mac mini, Mac Studio, Mac Pro, iMac |
| Sheds heat by | **slowing the chip down** | spinning fans up |
| Sustained heavy load | throttles after a few minutes | holds high clocks far longer |

```bash
sysctl -n hw.model            # e.g. Mac14,2 = MacBook Air (M2, fanless)
system_profiler SPHardwareDataType | grep "Model Name"   # the plain-English name
```
MacTweak detects this for you — the Dashboard's thermal card says *"This Mac is
fanless"* and reports live thermal pressure, so you can see whether you're
actually being throttled rather than guessing.

### The mechanism, in one paragraph

On a machine with fans, spare **cooling** is available on demand, so extra work
mostly costs you watts. On a fanless Mac, the ceiling is **thermal budget**, and
it is zero-sum: every joule a background daemon burns is a joule unavailable to
your foreground app, and heat it generates pushes the whole SoC closer to the
point where macOS lowers the clock ceiling for *everything*. So on an Air the
winning strategy is **removing competing work**, not unleashing more of it.

### What to change

| Tweak | Fanless (Air) | Actively cooled (Pro / desktop) |
|---|---|---|
| **Unthrottle Background I/O** | **Skip it.** | Reasonable. |
| **Server Performance Mode** | **Never.** | Only on a *desktop* doing real sustained server work. |
| **Disable Media Analysis / Photo Analysis / Spotlight indexing** | **High value.** | Nice-to-have. |
| **Keep Low Power Mode Off** | Depends on your workload — see below. | Yes, keep it off. |
| **Process Priority** | Prefer **Yield** on background hogs. | **Boost** actually helps. |

**Unthrottle Background I/O** (`debug.lowpri_throttle_enabled=0`) removes the
kernel's brake on low-priority disk work. That brake exists to keep background
jobs — Spotlight, Time Machine, sync clients — out of your way. On a fanned
machine, letting them run flat out is mostly free. On an Air you're handing
background work the same I/O bandwidth *and* thermal budget your foreground app
needs, which can make the thing you're actually waiting on slower. It's tagged
"performance", but on a fanless machine it often trades foreground
responsiveness for background completion time. Decide which you want.

**Server Performance Mode** biases the scheduler and memory for sustained
throughput, and it costs a reboot **and disabling SIP**. An Air can't sustain the
throughput it tunes for — you'll hit the thermal ceiling long before the
scheduler bias matters — so you'd be paying a real security price for a benefit
you can't collect. This one belongs on a Mac mini / Studio / Pro, not a laptop,
and least of all a fanless one.

**Background daemon disables** are the tweaks that gain the *most* from being on
an Air, for a reason that isn't obvious: it isn't only CPU contention. A photo-
analysis or re-index pass on a fanless machine raises thermal pressure, and once
pressure rises macOS derates the clock ceiling for your foreground work too. On a
fanned Pro the fan absorbs that pass and you may never notice it. Same tweak,
noticeably bigger real-world payoff on the Air.

**Keep Low Power Mode Off** is the one piece of common advice that deserves a
caveat on a fanless Mac. For bursty, interactive use — editors, browsers, short
builds — keep it off; you want the full clock range available. But if you're
doing *long* sustained work on an Air and the thermal card shows pressure
climbing, Low Power Mode is a legitimate tool rather than a compromise: capping
peak clocks means less heat, fewer throttle-and-recover swings, **more
predictable** performance, and a cooler chassis. Peak numbers drop; whether total
wall-clock time improves depends on the workload, so measure with
[Benchmark](../README.md) rather than assuming either way.

**Process Priority** cuts differently too. `renice` moves work around the
*scheduler*; it cannot raise a *thermal* ceiling. So on an Air, **Boost** (negative
nice) on a foreground app buys much less than you'd hope — the limit isn't
scheduling — while **Yield** (positive nice) on a background hog genuinely helps,
because it frees budget that is zero-sum. On a Pro with cooling headroom, Boost
has real headroom to exploit.

### Rule of thumb

> **Fanless:** subtract work. Disable background daemons, yield the hogs, leave
> the kernel's background brakes on.
> **Actively cooled:** you can afford to add. Unthrottling and boosting have
> headroom behind them.

The same "subtract work" logic applies to **when** you run maintenance, not just which
tweaks you apply. Reindexing Spotlight or wiping caches schedules a large rebuild, and
on a fanless Mac that rebuild competes for the same thermal budget as your foreground
app — see [FAQ: I cleaned my Mac and now it's hot](FAQ.md#i-cleaned-my-mac-and-now-its-hot-did-a-tweak-do-that).

Either way, verify rather than trust: the Dashboard thermal card shows whether
pressure is `Nominal` (full speed available) or elevated, and **Check speed**
samples real per-cluster MHz against the hardware maximum. Remember that cores
idling below maximum is normal — only the pressure level tells you the ceiling
actually moved.

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
| Stop Accidental VoiceOver | Snappiness | 🔓 | |
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
| Enable Application Firewall | Security & Network | 🔐 | safe |
| Enable Stealth Mode | Security & Network | 🔐 | safe · needs firewall on |
| Block Auto-Allow Signed Apps | Security & Network | 🔐 | moderate |
| Use Privacy DNS (Cloudflare) | Security & Network | 🔐 | moderate · plaintext |
| Disable IPv6 | Security & Network | 🔐 | ⚠️ |
| Enable TCP Window Scaling | Security & Network | 🔐 | ♻️ |
| Raise Max File Descriptors | Security & Network | 🔐 | ♻️ |
| Raise mDNSResponder | Process Priority | 🔐 | ♻️ |
| Raise Firefox | Process Priority | 🔐 | ♻️ |
| Raise Google Chrome | Process Priority | 🔐 | ♻️ |
| Raise Docker | Process Priority | 🔐 | ♻️ |
| Raise SSH sessions | Process Priority | 🔐 | ♻️ |
| Lower Media Analysis (yield CPU) | Process Priority | 🔐 | ♻️ |
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

### Stop Accidental VoiceOver — 🔓
Disables **⌘F5**, the shortcut behind the recurring *"Do you want to turn on
VoiceOver?"* dialog. VoiceOver itself is untouched — enable it from System Settings
whenever you actually want it.

This is symbolic hotkey **59** ("Turn VoiceOver on or off"). Both directions write the
*whole* entry, including the standard ⌘F5 binding (`65535` = no charCode, `96` = F5,
`1048576` = ⌘), so reverting restores a working shortcut instead of a bound-but-disabled
stub. `activateSettings -u` applies it without logging out.
```bash
# Apply
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 59 '<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>65535</integer><integer>96</integer><integer>1048576</integer></array><key>type</key><string>standard</string></dict></dict>' && /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
# Revert
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 59 '<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array><integer>65535</integer><integer>96</integer><integer>1048576</integer></array><key>type</key><string>standard</string></dict></dict>' && /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
```

> **Two triggers, and this covers only one.** The other is **triple-pressing Touch ID**
> (the "Accessibility Shortcut"), which has no `defaults` key — uncheck **VoiceOver** in
> **System Settings → Accessibility → Shortcut**. That's the usual culprit if the dialog
> appears "out of nowhere", since it's easy to trigger while authenticating.
>
> Note `com.apple.universalaccess voiceOverOnOffKey` is a *different, older* setting;
> it can already be `false` while ⌘F5 still works.

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

## 🛡️ Security & Network

`Stop Bonjour Advertising`, `Enlarge TCP Buffers` and `Raise Socket Backlog` (above,
under [Network](#-network)) live here too in the app — see that section for their
commands.

### Enable Application Firewall — 🔐
Turns on the built-in Application Firewall so unsolicited incoming connections are
blocked by default.
```bash
# Apply
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
# Revert
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off
# Check
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
```

### Enable Stealth Mode — 🔐 (needs firewall on)
Makes the Mac ignore ICMP ping and unsolicited probe packets instead of answering them.
```bash
# Apply
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
# Revert
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode off
# Check
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode
```

### Block Auto-Allow Signed Apps — 🔐
Stops the firewall from automatically trusting Apple-signed and developer-signed
apps — every app has to be approved individually. **More firewall prompts.**
```bash
# Apply
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setallowsigned off --setallowsignedapp off
# Revert
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setallowsigned on --setallowsignedapp on
# Check
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getallowsigned
```

### Use Privacy DNS (Cloudflare) — 🔐 (per network service)
Points DNS at Cloudflare's 1.1.1.1 / 1.0.0.1 privacy resolver instead of your ISP's
default. **Honest caveat:** this is still **plaintext DNS** — macOS has no CLI switch
for encrypted DNS-over-HTTPS/TLS, that requires a configuration profile. The app
applies this to **every active network service**; the command below targets Wi-Fi —
repeat with each name from `networksetup -listallnetworkservices` for the rest.
```bash
# Apply
sudo networksetup -setdnsservers Wi-Fi 1.1.1.1 1.0.0.1
# Revert
sudo networksetup -setdnsservers Wi-Fi Empty
# Check
networksetup -getdnsservers Wi-Fi
```

### Disable IPv6 — 🔐 ⚠️ (per network service)
Turns off IPv6 on a network service, shrinking the attack surface to IPv4 only.
Repeat per active service (Wi-Fi, Ethernet…). **Can break IPv6-only networks.**
```bash
# Apply
sudo networksetup -setv6off Wi-Fi
# Revert
sudo networksetup -setv6automatic Wi-Fi
# Check
networksetup -getinfo Wi-Fi
```

### Enable TCP Window Scaling — 🔐 ♻️
Raises the TCP window-scale factor so high-bandwidth, high-latency links can keep
more data in flight.
```bash
# Apply
sudo sysctl -w net.inet.tcp.win_scale_factor=8
# Revert
sudo sysctl -w net.inet.tcp.win_scale_factor=3
# Check
sysctl -n net.inet.tcp.win_scale_factor
```

### Raise Max File Descriptors — 🔐 ♻️
Raises the system-wide and per-process open-file limits, for apps and servers that
hit "too many open files" under load.
```bash
# Apply
sudo sysctl -w kern.maxfiles=524288 kern.maxfilesperproc=262144
# Revert
sudo sysctl -w kern.maxfiles=122880 kern.maxfilesperproc=61440
# Check
sysctl -n kern.maxfilesperproc
```

---

## 🎚️ Process Priority

Scheduling priority via `renice` — a **lower** nice value means **higher** CPU
priority (range −20…19, default 0). All resets on reboot unless you enable
**Apply at login** (below).

### Raise mDNSResponder — 🔐 ♻️
```bash
# Apply
sudo renice -n -5 -p $(pgrep mDNSResponder)
# Revert
sudo renice -n 0 -p $(pgrep mDNSResponder)
# Check
ps -o pid,nice,comm -p $(pgrep mDNSResponder)
```

### Raise Firefox — 🔐 ♻️
```bash
# Apply
sudo renice -n -5 -p $(pgrep -f "Firefox.app")
# Revert
sudo renice -n 0 -p $(pgrep -f "Firefox.app")
# Check
ps -o pid,nice,comm -p $(pgrep -f "Firefox.app")
```

### Raise Google Chrome — 🔐 ♻️
```bash
# Apply
sudo renice -n -5 -p $(pgrep -f "Google Chrome")
# Revert
sudo renice -n 0 -p $(pgrep -f "Google Chrome")
# Check
ps -o pid,nice,comm -p $(pgrep -f "Google Chrome")
```

### Raise Docker — 🔐 ♻️
```bash
# Apply
sudo renice -n -5 -p $(pgrep -f "com.docker")
# Revert
sudo renice -n 0 -p $(pgrep -f "com.docker")
# Check
ps -o pid,nice,comm -p $(pgrep -f "com.docker")
```

### Raise SSH sessions — 🔐 ♻️
```bash
# Apply
sudo renice -n -5 -p $(pgrep -f "sshd")
# Revert
sudo renice -n 0 -p $(pgrep -f "sshd")
# Check
ps -o pid,nice,comm -p $(pgrep -f "sshd")
```

### Lower Media Analysis (yield CPU) — 🔐 ♻️
Drops `mediaanalysisd`'s scheduling priority so it yields the CPU to whatever
you're actively doing.
```bash
# Apply
sudo renice -n 10 -p $(pgrep -f "mediaanalysisd")
# Revert
sudo renice -n 0 -p $(pgrep -f "mediaanalysisd")
# Check
ps -o pid,nice,comm -p $(pgrep -f "mediaanalysisd")
```

### Reset one process — 🔐
The manual escape hatch for a single PID.
```bash
sudo renice -n 0 -p <pid>
```

### Apply at login (persistence)

Because `renice` resets on reboot, MacTweak's **Apply at login** option writes a
per-target LaunchAgent that waits 15 seconds after login (so the target app has time
to launch), then reapplies the same `renice` through a passwordless sudo rule. Below
is the exact plist the app writes for Firefox — swap the label, path and `pgrep`
pattern to build one for another target.

`~/Library/LaunchAgents/com.mactweak.priority.firefox.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mactweak.priority.firefox</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>sleep 15; /usr/bin/sudo -n /bin/zsh -c 'renice -n -5 -p $(pgrep -f "Firefox.app")' 2>/dev/null; true</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
```
Load it:
```bash
launchctl load ~/Library/LaunchAgents/com.mactweak.priority.firefox.plist
```
Remove it:
```bash
launchctl unload ~/Library/LaunchAgents/com.mactweak.priority.firefox.plist; rm ~/Library/LaunchAgents/com.mactweak.priority.firefox.plist
```

> **Before you raise anything below −5:** the app caps every priority change at
> `-10` and warns before applying anything more negative than `-5` — an overly
> negative nice value can starve the UI and other apps of CPU time, making the whole
> Mac feel worse, not better. **Emergency reset:** run `sudo renice -n 0` on every
> process you've raised or lowered, then remove any
> `~/Library/LaunchAgents/com.mactweak.priority.*.plist` LaunchAgents you created.

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
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate   # security & network
ps -o pid,nice,comm -p $(pgrep mDNSResponder)                            # process priority
```
MacTweak does exactly this after every change — which is why it only marks a tweak
*Applied* when the system truly reports the new state.

See also: [SAFETY.md](SAFETY.md) · [FAQ.md](FAQ.md) · [ARCHITECTURE.md](ARCHITECTURE.md)
