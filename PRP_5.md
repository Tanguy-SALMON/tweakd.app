# Product Requirement Prompts (PRP): Security & Process Priority Module for MacTweak

## 1. Overview

This PRP defines the **Security & Process Priority** module for the **MacTweak** app – a native macOS menu‑bar utility that applies reversible system optimizations. The module extends MacTweak with two major feature areas:

- **Security Hardening** – firewall, stealth mode, network footprint reduction, TCP tuning, and DNS privacy.
- **Process Priority Management** – using `renice` to adjust CPU priority of network‑critical and system processes for improved responsiveness under load.

All features remain **reversible**, **transparent** (commands are shown to the user), and **safe** – the app only drives native macOS commands, never stores passwords, and includes an emergency revert script.

---

## 2. Goals

- Provide a **single‑click** way to enable/disable macOS security features that are typically hidden in System Settings or require terminal commands.
- Allow users to **fine‑tune network performance** (TCP buffers, window scaling, connection backlog) without digging into `sysctl`.
- Offer **process priority tuning** for network daemons (`mDNSResponder`), browsers (Firefox, Chrome), containers (Docker), and SSH – to reduce latency when CPU is saturated.
- Integrate these into MacTweak’s existing **Presets** and **Guided Setup** wizard, so users can choose profiles like “Security Hardened”, “Low‑Latency Networking”, or “AI Developer”.
- Maintain full **command‑line transparency** – every toggle’s Apply/Revert command is shown on the website and in the app’s “Show Commands” panel.

---

## 3. Feature Specifications

### 3.1 Security Hardening

| Feature | Description | macOS Command(s) | Risk Level | Requires Reboot? | SIP‑Dependent? |
|---------|-------------|------------------|------------|------------------|----------------|
| **Firewall – Enable** | Turns on the application firewall | `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on` | Safe | No | No |
| **Firewall – Stealth Mode** | Prevents responses to unsolicited probes (ping, closed ports) | `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on` | Safe | No | No |
| **Firewall – Disable Auto‑Allow Signed Apps** | Blocks incoming connections even for signed apps; manual whitelist required | `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setallowsigned off` | Moderate | No | No |
| **Disable Bonjour Advertising** | Stops mDNSResponder from broadcasting local services (AirDrop still works over AWDL) | `sudo defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool true && sudo killall -HUP mDNSResponder` | Moderate | No | No |
| **Disable IPv6** (optional) | Disables IPv6 on all interfaces | `sudo networksetup -setv6off Wi-Fi` (repeat for each service) | Advanced | No | No |
| **Limit Sharing Services** | Disables File Sharing, Printer Sharing, Remote Login, Remote Management, etc. (GUI only) | `sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server.plist Enabled -bool false; ...` | Safe | No | No |
| **Set DNS over HTTPS** (DoH) | Configures system‑wide DoH resolver (e.g., Cloudflare, Quad9) | `sudo networksetup -setdnsservers Wi-Fi 1.1.1.1; sudo networksetup -setdohservers Wi-Fi 1.1.1.1` | Safe | No | No |
| **TCP Buffer Tuning** | Increases max receive/send buffers to 16 MB (for high‑speed networks) | `sudo sysctl -w net.inet.tcp.autorcvbufmax=16777216 net.inet.tcp.autosndbufmax=16777216` | Moderate | Reset on reboot | No |
| **Increase Socket Backlog** | Raises `kern.ipc.somaxconn` to 1024 for servers | `sudo sysctl -w kern.ipc.somaxconn=1024` | Moderate | Reset on reboot | No |
| **Raise Max File Descriptors** | Allows more concurrent connections (server workloads) | `sudo sysctl -w kern.maxfiles=524288 kern.maxfilesperproc=262144` | Moderate | Reset on reboot | No |
| **Enable TCP Window Scaling** | Set scaling factor to 8 (more efficient for high‑latency links) | `sudo sysctl -w net.inet.tcp.win_scale_factor=8` | Moderate | Reset on reboot | No |

**Management:** Each feature is a toggle with an `Apply` and `Revert` command. The app verifies the current state using a `checkCommand` (e.g., `sysctl -n net.inet.tcp.autorcvbufmax`).

**UI:** Grouped under a new category **“Security & Network”** in the main settings panel.

---

### 3.2 Process Priority Management (renice)

| Feature | Description | macOS Command(s) | Risk Level | Persistence |
|---------|-------------|------------------|------------|-------------|
| **Raise mDNSResponder Priority** | Lowers nice value to -5 for faster DNS resolution | `sudo renice -n -5 -p $(pgrep mDNSResponder)` | Moderate | Resets on process restart; can be made permanent via launchd plist |
| **Raise Browser Priority** | Lowers nice value of Firefox/Chrome to -5 to improve page load responsiveness | `sudo renice -n -5 -p $(pgrep -f "Firefox")` | Moderate | Resets on browser restart |
| **Raise Docker Priority** | Lowers nice value of Docker processes (com.docker.vmnetd, etc.) to speed up container networking | `sudo renice -n -5 -p $(pgrep -f "com.docker")` | Moderate | Resets on Docker restart |
| **Raise SSH Priority** | Lowers nice value of active SSH connections for low‑latency terminal | `sudo renice -n -5 -p $(pgrep -f "sshd")` | Moderate | Resets on session end |
| **Lower Priority for Background Daemons** | Increases nice value (e.g., 10) for non‑critical services like mediaanalysisd to yield CPU to foreground tasks | `sudo renice -n 10 -p $(pgrep mediaanalysisd)` | Safe | Resets on daemon restart |

**Management:** Users can **select a process** from a live list (filtered by name) and set a desired nice value (slider or numeric input). The app will apply `renice` immediately. For persistence, the app can generate a launchd override file (or a script) to apply the priority at login.

**UI:** A new **“Process Priorities”** tab with:
- A table of detected processes (mDNSResponder, Firefox, Chrome, Docker, sshd, etc.).
- A slider/stepper for nice value (-20 to 20, with a “Reset to Default” button).
- A checkbox: “Apply at login” – if checked, the app creates a `~/Library/LaunchAgents/com.mactweak.priority.<name>.plist` that runs `renice` on the process after it starts (using `ProgramArguments` with `nice` or a wrapper script).

**Safety:** Always display a warning that overly high priority (negative) can cause system sluggishness. Provide an “Emergency Revert” button that resets all processes to nice 0.

---

## 4. Integration with Existing MacTweak

### 4.1 New Categories

- **Security & Network** – contains all firewall, stealth, Bonjour, TCP, and DoH toggles.
- **Process Priorities** – contains the process list and priority controls.

### 4.2 Presets

Add these presets to the existing list:

| Preset Name | Included Tweaks |
|-------------|-----------------|
| **Hardened Security** | Enable firewall, stealth mode, disable Bonjour advertising, disable auto‑allow signed apps, turn off sharing services, set DoH (Cloudflare). |
| **Low‑Latency Networking** | Raise TCP buffers, increase socket backlog, raise max files, enable TCP window scaling, and set mDNSResponder & browser to nice -5. |
| **Server / High Throughput** | Same as Low‑Latency but also raise max file descriptors, increase TCP buffers to 32 MB, and set nice -5 for Docker and sshd. |
| **Balanced** | Moderate tuning: firewall on, stealth on, buffers at 8 MB, and no priority changes. |

### 4.3 Guided Setup Integration

Extend the “How do you use your Mac?” wizard with new questions:
- “Do you run network services (web servers, SSH, containers)?” → enable server‑oriented tweaks.
- “Do you prioritise security over convenience?” → enable stealth, disable Bonjour, etc.
- “Do you need low latency for gaming or remote desktop?” → enable priority boosts for network processes.

### 4.4 Menubar Quick Actions

Add a new submenu:
- **Quick Security** → “Enable Firewall + Stealth” (single click)
- **Quick Network** → “Apply Low‑Latency Preset” (single click)
- **Reset Network/Process Priorities** → revert all network sysctls and renice to 0.

---

## 5. Implementation Plan (Phased)

### Phase 1: Core Managers

Create new Swift classes:

- **`SecurityManager`** – handles all firewall, stealth, Bonjour, sharing, DoH, and sysctl tweaks.
- **`PriorityManager`** – handles process discovery, `renice`, and persistence.

Both managers will use the existing `ShellExecutor` and store state in `UserDefaults`.

Example interface:

```swift
class SecurityManager: ObservableObject {
    func applyFirewall(enabled: Bool) -> Bool
    func applyStealth(enabled: Bool) -> Bool
    func applyBonjour(enabled: Bool) -> Bool
    func applyTCPBuffers(sizeMB: Int) -> Bool
    // ... and checkers
}

class PriorityManager: ObservableObject {
    @Published var processes: [PriorityProcess] = []
    func refreshProcessList() // runs pgrep and populates
    func setNice(for pid: Int, value: Int) -> Bool
    func createLaunchAgent(for pid: Int, nice: Int) -> Bool
    func removeLaunchAgent(for pid: Int)
}
```

### Phase 2: Security Toggles Implementation

For each toggle:

- Add a `Tweak` definition in `TweakManager` with appropriate `applyCommand`, `revertCommand`, `checkCommand`, and category `.security`.
- Implement the UI using `ToggleRow` – already exists.
- Add a `SecuritySettingsView` that groups these toggles.
- Ensure `checkCommand` accurately reads the current state (e.g., for firewall: `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`).

**Testing:** Verify each toggle changes the system state (using the check command) and reverts cleanly.

### Phase 3: Process Priority UI & Logic

- Create a `ProcessPriorityView` that displays a list of common processes (initially populated by a hardcoded list: `mDNSResponder`, `Firefox`, `Chrome`, `Docker`, `sshd`, `WindowServer`, etc.).
- Use `pgrep -f` to find PIDs; if multiple, show each as a row.
- Provide a slider for nice value with a label showing the current value (and a “Reset” button for that process).
- When the user adjusts the slider, call `PriorityManager.setNice(pid:value:)`. If successful, update the row’s status.
- For persistence: a checkbox “Apply at login”. If checked, `PriorityManager.createLaunchAgent()` writes a plist to `~/Library/LaunchAgents/com.mactweak.priority.<processName>.plist` that runs a script which waits for the process to start (using `pgrep -f` in a loop) and then runs `renice`. Alternatively, simpler: use `ProgramArguments` to launch the process with `nice -n <value>` – but that only works if we control the launch, not for system daemons. For system daemons, we can create a `launchctl` override by copying the original plist to `~/Library/LaunchDaemons/` and adding a `Nice` key – but that requires SIP‑off for system domains. For user agents, we can modify the user’s own launch agents. **Recommendation:** For system daemons, provide a one‑time `renice` and a warning that it resets on reboot; for user apps (browsers, Docker), we can create a launch agent that runs the app with `nice`.

**Simpler approach:** Offer a “Re‑apply priorities at login” option that runs a script via a LaunchAgent that executes `renice` on known PIDs after a short delay (using `sleep 10 && renice -n -5 -p $(pgrep -f Firefox)`). This is user‑friendly and doesn’t require SIP modifications.

### Phase 4: Presets and Guided Setup Integration

- Add new presets to `PresetManager` – define arrays of `Tweak` keys to enable/disable.
- Extend the Guided Setup wizard with two more steps:
  - Security preference: “Security Hardened”, “Balanced”, “Performance First”
  - Network usage: “Web browsing”, “Development (servers)”, “Gaming / low latency”
- Based on answers, the wizard will pre‑select appropriate toggles.

### Phase 5: Revert All & Emergency Script

- Update the existing “Revert All” function to also revert all security tweaks and reset all priorities to 0 (by running `sudo renice -n 0 -p <pid>` for each managed process).
- The emergency revert script (generated by the app) should include commands for each security toggle and renice reset.

### Phase 6: UI Polish & Error Handling

- Add a “Test Connection” button (optional) to measure latency before/after.
- Show a “Status” indicator for each toggle: green = applied, gray = not applied.
- Provide a “Show Commands” button that displays the exact terminal commands that would be run, for transparency.

### Phase 7: Documentation & Website Update

- Update the website’s “Security” and “Process Priority” sections with the exact commands as seen in the app (for manual users).
- Include clear warnings about `renice` and SIP (if applicable).

---

## 6. Deliverables

1. **`SecurityManager.swift`** – complete with all security toggles.
2. **`PriorityManager.swift`** – process discovery, renice, launch agent management.
3. **`SecuritySettingsView.swift`** – UI for security toggles.
4. **`ProcessPriorityView.swift`** – UI for priority management.
5. **Updated `TweakManager.swift`** – includes all new tweak definitions.
6. **Updated `PresetManager.swift`** – includes new presets.
7. **Updated Guided Setup** – new steps and logic.
8. **Updated `RevertAll` function** – handles security and priority reset.
9. **Updated website** – new sections with commands and explanations.
10. **Emergency revert script** – includes security and priority reset commands.

---

## 7. Testing & Validation

- **Test each toggle** individually on a test Mac (with and without SIP).
- **Test revert** for each toggle – ensure system returns to previous state.
- **Test priority changes** – use `top` to verify nice value changed.
- **Test persistence** – reboot and verify if launch agent works.
- **Test presets** – apply a preset and verify all toggles reflect expected state.
- **Performance before/after** – use `ping`, `curl -w`, `iperf3` to measure latency and throughput improvement (if applicable).
- **Test on different network environments** (Wi‑Fi, Ethernet, VPN).

---

## 8. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| **SIP** prevents some NVRAM/System daemon modifications | Clearly mark SIP‑dependent toggles; show a warning if SIP is on. |
| **`renice` set too low** (-20) may freeze the system | Limit slider to -10 for user; show warning for values below -5. |
| **Bonjour disable breaks AirPlay/AirDrop** | Add a prominent note that AirPlay/AirDrop may be affected. |
| **TCP buffer changes may degrade performance on slow networks** | Provide a “Reset to macOS default” button; show advice to only use on high‑speed networks. |
| **Launch agent persistence may not survive app updates** | Place generated plists in a separate directory and include a cleanup on uninstall. |

---

## 9. Success Criteria

- All security toggles apply and revert successfully.
- `renice` changes are applied immediately and verified.
- The app’s CPU/RAM gauges show no significant overhead when idle.
- The website accurately reflects all new commands.
- The guided setup produces a sensible configuration based on user responses.
- The “Revert All” function restores everything to stock.

---

## 10. Appendix: Example Commands for Reference

### Security

```bash
# Enable firewall + stealth
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

# Disable Bonjour advertising
sudo defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool true
sudo killall -HUP mDNSResponder

# Set DoH (Cloudflare)
sudo networksetup -setdnsservers Wi-Fi 1.1.1.1
sudo networksetup -setdohservers Wi-Fi 1.1.1.1

# TCP buffer 16MB
sudo sysctl -w net.inet.tcp.autorcvbufmax=16777216 net.inet.tcp.autosndbufmax=16777216
```

### Process Priority

```bash
# Raise mDNSResponder
sudo renice -n -5 -p $(pgrep mDNSResponder)

# Raise Firefox
sudo renice -n -5 -p $(pgrep -f Firefox)

# Create launch agent for Firefox persistence
cat > ~/Library/LaunchAgents/com.mactweak.priority.firefox.plist <<EOF
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
        <string>sleep 10 && renice -n -5 -p \$(pgrep -f Firefox)</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
EOF
launchctl load ~/Library/LaunchAgents/com.mactweak.priority.firefox.plist
```

---

## 11. Summary

This PRP provides a complete roadmap to extend MacTweak with **Security & Process Priority** features, maintaining the app’s core philosophy: **transparent, reversible, and always under the user’s control**. The implementation is divided into manageable phases, each with clear deliverables and test cases, ensuring a robust and user‑friendly outcome.

Once implemented, MacTweak will offer users a holistic system‑tuning experience – from UI snappiness to network security and process prioritisation – all through a beautiful, native menu‑bar app.
