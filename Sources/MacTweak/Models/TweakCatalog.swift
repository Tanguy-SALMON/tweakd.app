//
//  TweakCatalog.swift
//  MacTweak
//
//  The single source of truth for every tweak and one-shot action.
//  All commands here were verified against macOS 26 output formats.
//  Add a tweak = add one entry. Nothing else needs to change.
//

import Foundation

/// A one-off system action (no persistent on/off state).
struct SystemAction: Identifiable, Sendable {
    let key: String
    let title: String
    let summary: String
    let icon: String
    let privilege: Privilege
    let command: String
    let destructive: Bool
    var id: String { key }
    var runner: (String) -> CommandResult {
        privilege == .admin ? CommandRunner.admin : CommandRunner.user
    }
}

enum TweakCatalog {

    // Convenience so gui-domain commands always target the live user.
    private static let g = "gui/$(id -u)"

    static let all: [Tweak] = [

        // MARK: Performance
        Tweak(
            key: "timer-coalescing",
            title: "Disable Timer Coalescing",
            summary: "Stops the kernel from batching timers. Lower latency, slightly more wakeups.",
            category: .performance, privilege: .admin, risk: .moderate, sipRequired: false,
            applyCommand: "sysctl -w kern.timer.coalescing_enabled=0",
            revertCommand: "sysctl -w kern.timer.coalescing_enabled=1",
            statusCommand: "sysctl -n kern.timer.coalescing_enabled",
            appliedWhenOutputContains: "0",
            tags: [.prioritizePerformance, .serverWorkload], recommended: false
        ),
        Tweak(
            key: "disable-app-nap",
            title: "Disable App Nap",
            summary: "Keeps background apps running at full speed instead of being throttled.",
            category: .performance, privilege: .user, risk: .moderate, sipRequired: false,
            applyCommand: "defaults write -g NSAppSleepDisabled -bool YES",
            revertCommand: "defaults delete -g NSAppSleepDisabled 2>/dev/null; true",
            statusCommand: "defaults read -g NSAppSleepDisabled 2>/dev/null",
            appliedWhenOutputContains: "1",
            tags: [.prioritizePerformance], recommended: false
        ),

        // MARK: Power
        Tweak(
            key: "lowpowermode-off",
            title: "Keep Low Power Mode Off",
            summary: "Guarantees Low Power Mode stays disabled on all power sources.",
            category: .power, privilege: .admin, risk: .safe, sipRequired: false,
            applyCommand: "pmset -a lowpowermode 0",
            revertCommand: "pmset -a lowpowermode 1",
            statusCommand: "pmset -g | awk '/lowpowermode/{print $2}'",
            appliedWhenOutputContains: "0",
            tags: [.prioritizePerformance], recommended: true
        ),
        Tweak(
            key: "disable-powernap",
            title: "Disable Power Nap",
            summary: "Stops background wake-ups for mail, backups and updates while asleep.",
            category: .power, privilege: .admin, risk: .safe, sipRequired: false,
            applyCommand: "pmset -a powernap 0",
            revertCommand: "pmset -a powernap 1",
            statusCommand: "pmset -g | awk '/powernap/{print $2}'",
            appliedWhenOutputContains: "0",
            tags: [.prioritizeBattery, .prioritizePerformance], recommended: true
        ),
        Tweak(
            key: "disable-hibernation-image",
            title: "Skip Hibernation Image",
            summary: "Frees RAM-sized disk space and speeds sleep. You lose safe-sleep on battery loss.",
            category: .power, privilege: .admin, risk: .advanced, sipRequired: false,
            applyCommand: "pmset -a hibernatemode 0",
            revertCommand: "pmset -a hibernatemode 3",
            statusCommand: "pmset -g | awk '/hibernatemode/{print $2}'",
            appliedWhenOutputContains: "0",
            tags: [.prioritizePerformance], recommended: false
        ),

        // MARK: Snappiness (all safe, user-level, reversible)
        Tweak(
            key: "fast-window-resize",
            title: "Instant Window Resizing",
            summary: "Removes the animation when windows resize.",
            category: .snappiness, privilege: .user, risk: .safe, sipRequired: false,
            applyCommand: "defaults write -g NSWindowResizeTime -float 0.001",
            revertCommand: "defaults delete -g NSWindowResizeTime 2>/dev/null; true",
            statusCommand: "defaults read -g NSWindowResizeTime 2>/dev/null",
            appliedWhenOutputContains: "0.001",
            tags: [.snappyUI], recommended: true
        ),
        Tweak(
            key: "disable-window-anim",
            title: "Disable Window Animations",
            summary: "Turns off the open/close zoom on windows and dialogs.",
            category: .snappiness, privilege: .user, risk: .safe, sipRequired: false,
            applyCommand: "defaults write -g NSAutomaticWindowAnimationsEnabled -bool false",
            revertCommand: "defaults delete -g NSAutomaticWindowAnimationsEnabled 2>/dev/null; true",
            statusCommand: "defaults read -g NSAutomaticWindowAnimationsEnabled 2>/dev/null",
            appliedWhenOutputContains: "0",
            tags: [.snappyUI], recommended: true
        ),
        Tweak(
            key: "instant-dock",
            title: "Instant Dock Auto-Hide",
            summary: "Removes the delay before the Dock slides in and out.",
            category: .snappiness, privilege: .user, risk: .safe, sipRequired: false,
            applyCommand: "defaults write com.apple.dock autohide-delay -float 0 && defaults write com.apple.dock autohide-time-modifier -float 0.15 && killall Dock",
            revertCommand: "defaults delete com.apple.dock autohide-delay 2>/dev/null; defaults delete com.apple.dock autohide-time-modifier 2>/dev/null; killall Dock; true",
            statusCommand: "defaults read com.apple.dock autohide-delay 2>/dev/null",
            appliedWhenOutputContains: "0",
            tags: [.snappyUI], recommended: true
        ),
        Tweak(
            key: "fast-key-repeat",
            title: "Turbo Key Repeat",
            summary: "Fastest key repeat and shortest delay. Re-login to fully apply.",
            category: .snappiness, privilege: .user, risk: .safe, sipRequired: false,
            applyCommand: "defaults write -g KeyRepeat -int 2 && defaults write -g InitialKeyRepeat -int 15",
            revertCommand: "defaults delete -g KeyRepeat 2>/dev/null; defaults delete -g InitialKeyRepeat 2>/dev/null; true",
            statusCommand: "test \"$(defaults read -g KeyRepeat 2>/dev/null)\" = 2 && echo APPLIED",
            appliedWhenOutputContains: "APPLIED",
            tags: [.snappyUI], recommended: false
        ),

        // MARK: Privacy
        Tweak(
            key: "crashreporter-silent",
            title: "Silence Crash Reporter",
            summary: "Stops the 'application quit unexpectedly' dialogs.",
            category: .privacy, privilege: .user, risk: .safe, sipRequired: false,
            applyCommand: "defaults write com.apple.CrashReporter DialogType none",
            revertCommand: "defaults delete com.apple.CrashReporter DialogType 2>/dev/null; true",
            statusCommand: "defaults read com.apple.CrashReporter DialogType 2>/dev/null",
            appliedWhenOutputContains: "none",
            tags: [.privacyFocused], recommended: true
        ),
        Tweak(
            key: "disable-analyticsd",
            title: "Disable Diagnostics & Analytics",
            summary: "Turns off \"Share Mac Analytics\" and \"Share With App Developers\" — the same switch as System Settings › Privacy & Security › Analytics & Improvements.",
            category: .privacy, privilege: .admin, risk: .moderate, sipRequired: false,
            applyCommand: "defaults write /Library/Preferences/com.apple.SubmitDiagInfo AutoSubmit -bool false; defaults write /Library/Preferences/com.apple.SubmitDiagInfo ThirdPartyDataSubmit -bool false",
            revertCommand: "defaults write /Library/Preferences/com.apple.SubmitDiagInfo AutoSubmit -bool true; defaults write /Library/Preferences/com.apple.SubmitDiagInfo ThirdPartyDataSubmit -bool true",
            statusCommand: "defaults read /Library/Preferences/com.apple.SubmitDiagInfo AutoSubmit 2>/dev/null",
            appliedWhenOutputContains: "0",
            tags: [.privacyFocused], recommended: false
        ),
        Tweak(
            key: "disable-personalized-ads",
            title: "Disable Personalized Ads",
            summary: "Stops Apple Advertising from using your data to target ads. Works with SIP on.",
            category: .privacy, privilege: .user, risk: .safe, sipRequired: false,
            applyCommand: "defaults write com.apple.AdLib allowApplePersonalizedAdvertising -bool false",
            revertCommand: "defaults write com.apple.AdLib allowApplePersonalizedAdvertising -bool true",
            statusCommand: "defaults read com.apple.AdLib allowApplePersonalizedAdvertising 2>/dev/null",
            appliedWhenOutputContains: "0",
            tags: [.privacyFocused], recommended: true
        ),
        Tweak(
            key: "chromium-telemetry-off",
            title: "Harden Chromium & Chrome Telemetry",
            summary: "Sets managed-policy flags across Chromium/Chrome/Brave/Edge to stop usage stats, crash reports, URL data collection, search-keystroke and spell-check phone-home. Core Safe Browsing stays on; browsers show a 'managed' note. Takes effect on browser restart.",
            category: .privacy, privilege: .user, risk: .safe, sipRequired: false,
            applyCommand: "for d in org.chromium.Chromium com.google.Chrome com.brave.Browser com.microsoft.Edge; do defaults write \"$d\" MetricsReportingEnabled -bool false; defaults write \"$d\" UrlKeyedAnonymizedDataCollectionEnabled -bool false; defaults write \"$d\" SafeBrowsingExtendedReportingEnabled -bool false; defaults write \"$d\" SearchSuggestEnabled -bool false; defaults write \"$d\" SpellCheckServiceEnabled -bool false; done; true",
            revertCommand: "for d in org.chromium.Chromium com.google.Chrome com.brave.Browser com.microsoft.Edge; do for k in MetricsReportingEnabled UrlKeyedAnonymizedDataCollectionEnabled SafeBrowsingExtendedReportingEnabled SearchSuggestEnabled SpellCheckServiceEnabled; do defaults delete \"$d\" \"$k\" 2>/dev/null; done; done; true",
            statusCommand: "for d in org.chromium.Chromium com.google.Chrome com.brave.Browser com.microsoft.Edge; do defaults read \"$d\" MetricsReportingEnabled 2>/dev/null; done",
            appliedWhenOutputContains: "0",
            tags: [.privacyFocused], recommended: false
        ),
        Tweak(
            key: "firefox-telemetry-off",
            title: "Disable Firefox Telemetry",
            summary: "Writes a managed user.js into every Firefox profile to turn off telemetry, health-report upload, Shield studies, ping-centre and new-tab data collection. No admin, survives updates, and replaces any existing user.js. Takes effect on Firefox restart.",
            category: .privacy, privilege: .user, risk: .moderate, sipRequired: false,
            applyCommand: "for p in \"$HOME/Library/Application Support/Firefox/Profiles/\"*/; do [ -d \"$p\" ] || continue; /usr/bin/printf '%s\\n' '// MacTweak privacy — Firefox telemetry off' 'user_pref(\"toolkit.telemetry.enabled\", false);' 'user_pref(\"toolkit.telemetry.unified\", false);' 'user_pref(\"toolkit.telemetry.archive.enabled\", false);' 'user_pref(\"datareporting.healthreport.uploadEnabled\", false);' 'user_pref(\"datareporting.policy.dataSubmissionEnabled\", false);' 'user_pref(\"app.shield.optoutstudies.enabled\", false);' 'user_pref(\"browser.ping-centre.telemetry\", false);' 'user_pref(\"browser.newtabpage.activity-stream.feeds.telemetry\", false);' 'user_pref(\"browser.newtabpage.activity-stream.telemetry\", false);' 'user_pref(\"browser.discovery.enabled\", false);' > \"$p/user.js\"; done; true",
            revertCommand: "for p in \"$HOME/Library/Application Support/Firefox/Profiles/\"*/; do f=\"$p/user.js\"; if [ -f \"$f\" ] && /usr/bin/grep -q 'MacTweak privacy' \"$f\"; then /bin/rm -f \"$f\"; fi; done; true",
            statusCommand: "/bin/cat \"$HOME/Library/Application Support/Firefox/Profiles/\"*/user.js 2>/dev/null | /usr/bin/grep 'MacTweak privacy'",
            appliedWhenOutputContains: "MacTweak privacy",
            tags: [.privacyFocused], recommended: false
        ),

        // MARK: Background Services (user agents — no SIP needed)
        Tweak(
            key: "disable-mediaanalysisd",
            title: "Disable Media Analysis",
            summary: "Stops background scanning of photos/videos for objects and scenes.",
            category: .services, privilege: .user, risk: .moderate, sipRequired: false,
            applyCommand: "launchctl disable \(g)/com.apple.mediaanalysisd; launchctl bootout \(g)/com.apple.mediaanalysisd 2>/dev/null; true",
            revertCommand: "launchctl enable \(g)/com.apple.mediaanalysisd",
            statusCommand: "launchctl print-disabled \(g) 2>/dev/null | grep mediaanalysisd",
            appliedWhenOutputContains: "disabled",
            tags: [.usesPhotos, .usesAI], recommended: true
        ),
        Tweak(
            key: "disable-photoanalysisd",
            title: "Disable Photo Analysis",
            summary: "Stops face recognition and Memories generation in Photos.",
            category: .services, privilege: .user, risk: .moderate, sipRequired: false,
            applyCommand: "launchctl disable \(g)/com.apple.photoanalysisd; launchctl bootout \(g)/com.apple.photoanalysisd 2>/dev/null; true",
            revertCommand: "launchctl enable \(g)/com.apple.photoanalysisd",
            statusCommand: "launchctl print-disabled \(g) 2>/dev/null | grep photoanalysisd",
            appliedWhenOutputContains: "disabled",
            tags: [.usesPhotos], recommended: true
        ),
        Tweak(
            key: "disable-spotlight",
            title: "Disable Spotlight Indexing",
            summary: "Turns off filesystem indexing on all volumes. Search still opens apps.",
            category: .services, privilege: .admin, risk: .advanced, sipRequired: false,
            applyCommand: "mdutil -a -i off",
            revertCommand: "mdutil -a -i on",
            statusCommand: "mdutil -s /",
            appliedWhenOutputContains: "disabled",
            tags: [.usesSpotlight], recommended: false
        ),

        // MARK: Network
        Tweak(
            key: "mdns-no-advertise",
            title: "Stop Bonjour Advertising",
            summary: "Stops broadcasting services over Bonjour. AirDrop keeps working over AWDL.",
            category: .security, privilege: .admin, risk: .moderate, sipRequired: false,
            applyCommand: "defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool true; killall -HUP mDNSResponder 2>/dev/null; true",
            revertCommand: "defaults delete /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements 2>/dev/null; killall -HUP mDNSResponder 2>/dev/null; true",
            statusCommand: "defaults read /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements 2>/dev/null",
            appliedWhenOutputContains: "1",
            tags: [.usesAirDropAirPlay, .privacyFocused], recommended: false
        ),
        // Throughput tuning for local servers / dev tooling (PRP_4). Both reset on reboot.
        Tweak(
            key: "tcp-buffers",
            title: "Enlarge TCP Buffers",
            summary: "Raises max TCP send/receive buffers to 16 MB for higher throughput on busy local servers. Resets on reboot.",
            category: .security, privilege: .admin, risk: .moderate, sipRequired: false,
            applyCommand: "sysctl -w net.inet.tcp.autorcvbufmax=16777216 net.inet.tcp.autosndbufmax=16777216",
            revertCommand: "sysctl -w net.inet.tcp.autorcvbufmax=4194304 net.inet.tcp.autosndbufmax=4194304",
            statusCommand: "[ \"$(sysctl -n net.inet.tcp.autorcvbufmax)\" -gt 4194304 ] && echo ON || echo OFF",
            appliedWhenOutputContains: "ON",
            tags: [.prioritizePerformance, .serverWorkload, .lowLatency], recommended: false
        ),
        Tweak(
            key: "socket-backlog",
            title: "Raise Socket Backlog",
            summary: "Raises the max pending-connection queue (somaxconn) from 128 to 1024 so servers accept bursts of connections. Resets on reboot.",
            category: .security, privilege: .admin, risk: .moderate, sipRequired: false,
            applyCommand: "sysctl -w kern.ipc.somaxconn=1024",
            revertCommand: "sysctl -w kern.ipc.somaxconn=128",
            statusCommand: "[ \"$(sysctl -n kern.ipc.somaxconn)\" -gt 128 ] && echo ON || echo OFF",
            appliedWhenOutputContains: "ON",
            tags: [.prioritizePerformance, .serverWorkload, .lowLatency], recommended: false
        ),

        // MARK: Security & Network hardening
        Tweak(
            key: "firewall-enable",
            title: "Enable Application Firewall",
            summary: "Turns on the built-in application firewall to block unsolicited incoming connections.",
            category: .security, privilege: .admin, risk: .safe, sipRequired: false,
            applyCommand: "/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on",
            revertCommand: "/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off",
            statusCommand: "/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q 'State = 1' && echo ON || echo OFF",
            appliedWhenOutputContains: "ON",
            tags: [.security, .privacyFocused], recommended: true
        ),
        Tweak(
            key: "firewall-stealth",
            title: "Enable Stealth Mode",
            summary: "Your Mac stops replying to pings/probes on closed ports. Needs the firewall on.",
            category: .security, privilege: .admin, risk: .safe, sipRequired: false,
            applyCommand: "/usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on",
            revertCommand: "/usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode off",
            statusCommand: "/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null | grep -qiE 'on|enabled' && echo ON || echo OFF",
            appliedWhenOutputContains: "ON",
            tags: [.security, .privacyFocused], recommended: false
        ),
        Tweak(
            key: "firewall-block-signed",
            title: "Block Auto-Allow Signed Apps",
            summary: "Even signed apps must be approved for incoming connections. You'll get more firewall prompts.",
            category: .security, privilege: .admin, risk: .moderate, sipRequired: false,
            applyCommand: "/usr/libexec/ApplicationFirewall/socketfilterfw --setallowsigned off --setallowsignedapp off",
            revertCommand: "/usr/libexec/ApplicationFirewall/socketfilterfw --setallowsigned on --setallowsignedapp on",
            statusCommand: "/usr/libexec/ApplicationFirewall/socketfilterfw --getallowsigned 2>/dev/null | grep -qi disabled && echo ON || echo OFF",
            appliedWhenOutputContains: "ON",
            tags: [.security], recommended: false
        ),
        Tweak(
            key: "dns-privacy",
            title: "Use Privacy DNS (Cloudflare)",
            summary: "Routes DNS for every network service to Cloudflare's 1.1.1.1/1.0.0.1 privacy resolver. This is plaintext DNS — macOS has no built-in command to enable encrypted DNS-over-HTTPS (that needs a configuration profile). Reverts to your DHCP-provided DNS.",
            category: .security, privilege: .admin, risk: .moderate, sipRequired: false,
            applyCommand: "networksetup -listallnetworkservices | tail -n +2 | sed 's/^\\* //' | while IFS= read -r s; do networksetup -setdnsservers \"$s\" 1.1.1.1 1.0.0.1; done; true",
            revertCommand: "networksetup -listallnetworkservices | tail -n +2 | sed 's/^\\* //' | while IFS= read -r s; do networksetup -setdnsservers \"$s\" Empty; done; true",
            statusCommand: "networksetup -listallnetworkservices | tail -n +2 | sed 's/^\\* //' | while IFS= read -r s; do networksetup -getdnsservers \"$s\"; done | grep -q 1.1.1.1 && echo ON || echo OFF",
            appliedWhenOutputContains: "ON",
            tags: [.security, .privacyFocused], recommended: false
        ),
        Tweak(
            key: "disable-ipv6",
            title: "Disable IPv6",
            summary: "Turns off IPv6 on all network services. Advanced — can break IPv6-only networks; leave off unless you know you want it.",
            category: .security, privilege: .admin, risk: .advanced, sipRequired: false,
            applyCommand: "networksetup -listallnetworkservices | tail -n +2 | sed 's/^\\* //' | while IFS= read -r s; do networksetup -setv6off \"$s\"; done; true",
            revertCommand: "networksetup -listallnetworkservices | tail -n +2 | sed 's/^\\* //' | while IFS= read -r s; do networksetup -setv6automatic \"$s\"; done; true",
            statusCommand: "networksetup -listallnetworkservices | tail -n +2 | sed 's/^\\* //' | while IFS= read -r s; do networksetup -getinfo \"$s\"; done | grep -q 'IPv6: Off' && echo ON || echo OFF",
            appliedWhenOutputContains: "ON",
            tags: [.security], recommended: false
        ),
        Tweak(
            key: "tcp-window-scaling",
            title: "Enable TCP Window Scaling",
            summary: "Raises the TCP window scaling factor to 8 for better throughput on high-latency/high-bandwidth links. Resets on reboot.",
            category: .security, privilege: .admin, risk: .moderate, sipRequired: false,
            applyCommand: "sysctl -w net.inet.tcp.win_scale_factor=8",
            revertCommand: "sysctl -w net.inet.tcp.win_scale_factor=3",
            statusCommand: "[ \"$(sysctl -n net.inet.tcp.win_scale_factor)\" -gt 3 ] && echo ON || echo OFF",
            appliedWhenOutputContains: "ON",
            tags: [.lowLatency, .serverWorkload], recommended: false
        ),
        Tweak(
            key: "max-file-descriptors",
            title: "Raise Max File Descriptors",
            summary: "Allows far more concurrent open files/sockets for servers and heavy dev workloads. Resets on reboot.",
            category: .security, privilege: .admin, risk: .moderate, sipRequired: false,
            applyCommand: "sysctl -w kern.maxfiles=524288 kern.maxfilesperproc=262144",
            revertCommand: "sysctl -w kern.maxfiles=122880 kern.maxfilesperproc=61440",
            statusCommand: "[ \"$(sysctl -n kern.maxfilesperproc)\" -gt 61440 ] && echo ON || echo OFF",
            appliedWhenOutputContains: "ON",
            tags: [.serverWorkload], recommended: false
        ),

        // MARK: AI & Intelligence
        Tweak(
            key: "disable-siri-daemon",
            title: "Disable Siri Assistant",
            summary: "Boots out the Siri assistant agent and hides its menu bar item.",
            category: .ai, privilege: .user, risk: .moderate, sipRequired: false,
            applyCommand: "defaults write com.apple.Siri StatusMenuVisible -bool false; launchctl disable \(g)/com.apple.assistantd; launchctl bootout \(g)/com.apple.assistantd 2>/dev/null; true",
            revertCommand: "defaults delete com.apple.Siri StatusMenuVisible 2>/dev/null; launchctl enable \(g)/com.apple.assistantd; true",
            statusCommand: "launchctl print-disabled \(g) 2>/dev/null | grep assistantd",
            appliedWhenOutputContains: "disabled",
            tags: [.usesAI], recommended: false
        ),
        Tweak(
            key: "disable-duetexpertd",
            title: "Disable Proactive Intelligence",
            summary: "Stops duetexpertd — the on-device daemon behind Siri Suggestions and predicted actions.",
            category: .ai, privilege: .user, risk: .moderate, sipRequired: false,
            applyCommand: "launchctl disable \(g)/com.apple.duetexpertd; launchctl bootout \(g)/com.apple.duetexpertd 2>/dev/null; true",
            revertCommand: "launchctl enable \(g)/com.apple.duetexpertd; true",
            statusCommand: "launchctl print-disabled \(g) 2>/dev/null | grep duetexpertd",
            appliedWhenOutputContains: "disabled",
            tags: [.usesAI, .privacyFocused], recommended: false
        ),
        Tweak(
            key: "disable-lookup-suggestions",
            title: "Disable Siri Suggestions in Lookup",
            summary: "Stops sending lookup queries for Siri-powered suggestions.",
            category: .ai, privilege: .user, risk: .safe, sipRequired: false,
            applyCommand: "defaults write com.apple.lookup.shared LookupSuggestionsDisabled -bool true",
            revertCommand: "defaults delete com.apple.lookup.shared LookupSuggestionsDisabled 2>/dev/null; true",
            statusCommand: "defaults read com.apple.lookup.shared LookupSuggestionsDisabled 2>/dev/null",
            appliedWhenOutputContains: "1",
            tags: [.usesAI, .privacyFocused], recommended: true
        ),

        // MARK: CPU & GPU speed (verified on Apple Silicon / macOS 26)
        Tweak(
            key: "raise-gpu-vram",
            title: "Raise GPU Memory Limit",
            summary: "Lets the GPU use up to ~75% of RAM (great for local ML/graphics). Resets on reboot.",
            category: .performance, privilege: .admin, risk: .advanced, sipRequired: false,
            applyCommand: "sysctl -w iogpu.wired_limit_mb=$(( $(sysctl -n hw.memsize)/1024/1024*3/4 ))",
            revertCommand: "sysctl -w iogpu.wired_limit_mb=0",
            statusCommand: "[ \"$(sysctl -n iogpu.wired_limit_mb)\" -gt 0 ] && echo RAISED || echo DEFAULT",
            appliedWhenOutputContains: "RAISED",
            tags: [.prioritizePerformance], recommended: false
        ),
        Tweak(
            key: "disable-lowpri-throttle",
            title: "Unthrottle Background I/O",
            summary: "Stops the kernel from throttling low-priority disk work, so background tasks finish faster.",
            category: .performance, privilege: .admin, risk: .moderate, sipRequired: false,
            applyCommand: "sysctl -w debug.lowpri_throttle_enabled=0",
            revertCommand: "sysctl -w debug.lowpri_throttle_enabled=1",
            statusCommand: "sysctl -n debug.lowpri_throttle_enabled",
            appliedWhenOutputContains: "0",
            tags: [.prioritizePerformance, .serverWorkload], recommended: false
        ),
        Tweak(
            key: "serverperfmode",
            title: "Server Performance Mode",
            summary: "Biases the scheduler and memory for sustained throughput. Needs SIP off + reboot; preserves other boot-args.",
            category: .performance, privilege: .admin, risk: .advanced, sipRequired: true,
            // Prepend serverperfmode while keeping any existing boot-args (nvram prints "boot-args\t<value>").
            applyCommand: "nvram boot-args=\"serverperfmode=1 $(nvram boot-args 2>/dev/null | cut -f2-)\"",
            revertCommand: "nvram -d boot-args",
            statusCommand: "nvram boot-args 2>/dev/null | grep -q serverperfmode && echo ON || echo OFF",
            appliedWhenOutputContains: "ON",
            tags: [.prioritizePerformance, .serverWorkload], recommended: false
        ),

        // MARK: Responsiveness — WindowServer / Finder / Dock (all safe, reversible)
        Tweak(
            key: "reduce-transparency",
            title: "Reduce Transparency",
            summary: "Cuts WindowServer GPU and RAM use by removing translucency and blur.",
            category: .snappiness, privilege: .user, risk: .safe, sipRequired: false,
            applyCommand: "defaults write com.apple.universalaccess reduceTransparency -bool true",
            revertCommand: "defaults delete com.apple.universalaccess reduceTransparency 2>/dev/null; true",
            statusCommand: "defaults read com.apple.universalaccess reduceTransparency 2>/dev/null",
            appliedWhenOutputContains: "1",
            tags: [.snappyUI, .prioritizePerformance], recommended: true
        ),
        Tweak(
            key: "reduce-motion",
            title: "Reduce Motion",
            summary: "Replaces Spaces/app-switch animations with quick fades. Snappier, less GPU work.",
            category: .snappiness, privilege: .user, risk: .safe, sipRequired: false,
            applyCommand: "defaults write com.apple.universalaccess reduceMotion -bool true",
            revertCommand: "defaults delete com.apple.universalaccess reduceMotion 2>/dev/null; true",
            statusCommand: "defaults read com.apple.universalaccess reduceMotion 2>/dev/null",
            appliedWhenOutputContains: "1",
            tags: [.snappyUI], recommended: false
        ),
        Tweak(
            key: "disable-finder-anim",
            title: "Disable Finder Animations",
            summary: "Removes Finder's open/copy/resize animations. Relaunches Finder.",
            category: .snappiness, privilege: .user, risk: .safe, sipRequired: false,
            applyCommand: "defaults write com.apple.finder DisableAllAnimations -bool true && killall Finder",
            revertCommand: "defaults delete com.apple.finder DisableAllAnimations 2>/dev/null; killall Finder; true",
            statusCommand: "defaults read com.apple.finder DisableAllAnimations 2>/dev/null",
            appliedWhenOutputContains: "1",
            tags: [.snappyUI], recommended: false
        ),
        Tweak(
            key: "dock-scale-minimize",
            title: "Fast Minimize Effect",
            summary: "Uses the lightweight Scale effect instead of the Genie animation. Relaunches Dock.",
            category: .snappiness, privilege: .user, risk: .safe, sipRequired: false,
            applyCommand: "defaults write com.apple.dock mineffect -string scale && killall Dock",
            revertCommand: "defaults delete com.apple.dock mineffect 2>/dev/null; killall Dock; true",
            statusCommand: "defaults read com.apple.dock mineffect 2>/dev/null",
            appliedWhenOutputContains: "scale",
            tags: [.snappyUI], recommended: true
        ),
        Tweak(
            key: "disable-launch-bounce",
            title: "Disable App Launch Bounce",
            summary: "Stops the Dock icon from bouncing while apps open. Relaunches Dock.",
            category: .snappiness, privilege: .user, risk: .safe, sipRequired: false,
            applyCommand: "defaults write com.apple.dock launchanim -bool false && killall Dock",
            revertCommand: "defaults delete com.apple.dock launchanim 2>/dev/null; killall Dock; true",
            statusCommand: "defaults read com.apple.dock launchanim 2>/dev/null",
            appliedWhenOutputContains: "0",
            tags: [.snappyUI], recommended: false
        ),

        // MARK: Snappiness — verified subset from the beta list (PRP_2)
        Tweak(
            key: "fast-mission-control",
            title: "Faster Mission Control",
            summary: "Removes the Mission Control / App Exposé zoom animation.",
            category: .snappiness, privilege: .user, risk: .safe, sipRequired: false,
            applyCommand: "defaults write com.apple.dock expose-animation-duration -float 0 && killall Dock",
            revertCommand: "defaults delete com.apple.dock expose-animation-duration 2>/dev/null; killall Dock; true",
            statusCommand: "[ \"$(defaults read com.apple.dock expose-animation-duration 2>/dev/null)\" = \"0\" ] && echo ON || echo OFF",
            appliedWhenOutputContains: "ON",
            tags: [.snappyUI], recommended: false
        ),
        Tweak(
            key: "instant-fullscreen-menubar",
            title: "Instant Fullscreen Menu Bar",
            summary: "Removes the delay before the menu bar reveals in fullscreen apps.",
            category: .snappiness, privilege: .user, risk: .safe, sipRequired: false,
            applyCommand: "defaults write com.apple.dock fullscreen-delay -float 0 && killall Dock",
            revertCommand: "defaults delete com.apple.dock fullscreen-delay 2>/dev/null; killall Dock; true",
            statusCommand: "[ \"$(defaults read com.apple.dock fullscreen-delay 2>/dev/null)\" = \"0\" ] && echo ON || echo OFF",
            appliedWhenOutputContains: "ON",
            tags: [.snappyUI], recommended: false
        ),
        Tweak(
            key: "disable-smooth-scroll",
            title: "Disable Smooth Scrolling",
            summary: "Step-based scrolling instead of animated. Saves CPU when scrolling heavily.",
            category: .snappiness, privilege: .user, risk: .moderate, sipRequired: false,
            applyCommand: "defaults write -g NSScrollAnimationEnabled -bool false",
            revertCommand: "defaults delete -g NSScrollAnimationEnabled 2>/dev/null; true",
            statusCommand: "defaults read -g NSScrollAnimationEnabled 2>/dev/null",
            appliedWhenOutputContains: "0",
            tags: [.snappyUI, .prioritizePerformance], recommended: false
        ),
        Tweak(
            key: "manual-window-tabbing",
            title: "Manual Window Tabbing",
            summary: "Stops apps from auto-merging windows into tabs. Trims WindowServer work.",
            category: .snappiness, privilege: .user, risk: .moderate, sipRequired: false,
            applyCommand: "defaults write -g AppleWindowTabbingMode -string manual",
            revertCommand: "defaults delete -g AppleWindowTabbingMode 2>/dev/null; true",
            statusCommand: "defaults read -g AppleWindowTabbingMode 2>/dev/null",
            appliedWhenOutputContains: "manual",
            tags: [.snappyUI], recommended: false
        ),
    ]

    /// A distinct, hand-picked SF Symbol per tweak so every row reads uniquely.
    static let iconOverrides: [String: String] = [
        // Performance
        "timer-coalescing": "timer",
        "disable-app-nap": "moon.zzz",
        "raise-gpu-vram": "memorychip",
        "disable-lowpri-throttle": "speedometer",
        "serverperfmode": "server.rack",
        // Power
        "lowpowermode-off": "battery.100.bolt",
        "disable-powernap": "powersleep",
        "disable-hibernation-image": "bed.double",
        // Snappiness
        "fast-window-resize": "arrow.up.left.and.arrow.down.right",
        "disable-window-anim": "macwindow",
        "instant-dock": "dock.rectangle",
        "fast-key-repeat": "keyboard",
        "fast-mission-control": "square.grid.3x3",
        "instant-fullscreen-menubar": "menubar.rectangle",
        "disable-smooth-scroll": "scroll",
        "manual-window-tabbing": "rectangle.stack",
        "reduce-transparency": "circle.righthalf.filled",
        "reduce-motion": "tortoise",
        "disable-finder-anim": "folder",
        "dock-scale-minimize": "arrow.down.right.and.arrow.up.left",
        "disable-launch-bounce": "arrow.up.forward.app",
        // Privacy
        "crashreporter-silent": "exclamationmark.bubble",
        "disable-analyticsd": "antenna.radiowaves.left.and.right",
        "disable-personalized-ads": "hand.raised",
        "chromium-telemetry-off": "globe.badge.chevron.backward",
        "firefox-telemetry-off": "flame",
        // Background services
        "disable-mediaanalysisd": "film",
        "disable-photoanalysisd": "person.crop.rectangle.stack",
        "disable-spotlight": "magnifyingglass",
        // Network
        "mdns-no-advertise": "dot.radiowaves.left.and.right",
        "tcp-buffers": "arrow.up.arrow.down.circle",
        "socket-backlog": "square.stack.3d.up",
        "firewall-enable": "shield.lefthalf.filled",
        "firewall-stealth": "eye.slash",
        "firewall-block-signed": "hand.raised.slash",
        "dns-privacy": "lock.badge.clock",
        "disable-ipv6": "6.circle",
        "tcp-window-scaling": "arrow.left.and.right",
        "max-file-descriptors": "doc.on.doc",
        // AI & Intelligence
        "disable-siri-daemon": "mic",
        "disable-lookup-suggestions": "text.magnifyingglass",
        "disable-duetexpertd": "brain",
    ]

    /// What each tweak improves — mirrors the website's gain chips exactly.
    static let gainsByKey: [String: [Gain]] = [
        // Performance & power → raw speed
        "timer-coalescing": [.faster], "disable-app-nap": [.faster], "raise-gpu-vram": [.faster],
        "disable-lowpri-throttle": [.faster], "serverperfmode": [.faster], "lowpowermode-off": [.faster],
        "disable-powernap": [.battery], "disable-hibernation-image": [.disk],
        // Snappiness → responsiveness
        "fast-window-resize": [.snappier], "disable-window-anim": [.snappier], "instant-dock": [.snappier],
        "fast-key-repeat": [.snappier], "fast-mission-control": [.snappier],
        "instant-fullscreen-menubar": [.snappier], "disable-smooth-scroll": [.snappier],
        "manual-window-tabbing": [.snappier], "reduce-transparency": [.snappier, .frees],
        "reduce-motion": [.snappier], "disable-finder-anim": [.snappier],
        "dock-scale-minimize": [.snappier], "disable-launch-bounce": [.snappier],
        // Privacy
        "crashreporter-silent": [.privacy], "disable-personalized-ads": [.privacy],
        "disable-analyticsd": [.privacy], "chromium-telemetry-off": [.privacy],
        "firefox-telemetry-off": [.privacy], "mdns-no-advertise": [.privacy],
        "disable-lookup-suggestions": [.privacy],
        // Background services & AI daemons → frees resources (+ privacy)
        "disable-mediaanalysisd": [.frees, .privacy], "disable-photoanalysisd": [.frees, .privacy],
        "disable-spotlight": [.frees], "disable-siri-daemon": [.frees, .privacy],
        "disable-duetexpertd": [.frees, .privacy],
        // Network throughput
        "tcp-buffers": [.throughput, .latency], "socket-backlog": [.throughput, .latency],
        // Security & network hardening
        "firewall-enable": [.secure, .privacy], "firewall-stealth": [.secure, .privacy],
        "firewall-block-signed": [.secure], "dns-privacy": [.privacy, .secure],
        "disable-ipv6": [.secure], "tcp-window-scaling": [.throughput, .latency],
        "max-file-descriptors": [.throughput],
    ]

    // MARK: - One-shot actions

    static let actions: [SystemAction] = [
        SystemAction(
            key: "purge-memory",
            title: "Purge Inactive Memory",
            summary: "Forces the memory manager to free inactive pages right now.",
            icon: "memorychip", privilege: .admin,
            command: "purge", destructive: false
        ),
        SystemAction(
            key: "flush-dns",
            title: "Flush DNS Cache",
            summary: "Clears resolver cache and reloads mDNSResponder.",
            icon: "arrow.triangle.2.circlepath", privilege: .admin,
            command: "dscacheutil -flushcache; killall -HUP mDNSResponder", destructive: false
        ),
        SystemAction(
            key: "restart-ui",
            title: "Restart Dock & Finder",
            summary: "Applies UI tweaks and clears stuck windows.",
            icon: "menubar.dock.rectangle", privilege: .user,
            command: "killall Dock Finder; true", destructive: false
        ),
        SystemAction(
            key: "purge-bloat",
            title: "Purge Bloat Daemons Now",
            summary: "Sends a polite terminate to heavy AI/analytics daemons. They may respawn.",
            icon: "wind", privilege: .admin,
            command: "for p in mediaanalysisd photoanalysisd analyticsd spotlightknowledged knowledgeconstructiond geoanalyticsd; do killall -TERM $p 2>/dev/null; done; true",
            destructive: false
        ),
        SystemAction(
            key: "restart-coreaudio",
            title: "Restart Core Audio",
            summary: "Restarts coreaudiod to fix stuck audio or runaway CPU. It relaunches automatically; audio blips for a second.",
            icon: "waveform", privilege: .admin,
            command: "killall coreaudiod 2>/dev/null; true", destructive: false
        ),
        SystemAction(
            key: "reindex-spotlight",
            title: "Rebuild Spotlight Index",
            summary: "Erases and rebuilds the Spotlight index for the boot volume.",
            icon: "magnifyingglass", privilege: .admin,
            command: "mdutil -E /", destructive: true
        ),
    ]
}
