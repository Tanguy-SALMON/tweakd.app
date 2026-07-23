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
            tags: [.prioritizePerformance], recommended: false
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
            statusCommand: "defaults read -g KeyRepeat 2>/dev/null",
            appliedWhenOutputContains: "2",
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
            summary: "Stops the analyticsd telemetry daemon. Requires SIP to be disabled.",
            category: .privacy, privilege: .admin, risk: .moderate, sipRequired: true,
            applyCommand: "launchctl disable system/com.apple.analyticsd; launchctl bootout system/com.apple.analyticsd 2>/dev/null; true",
            revertCommand: "launchctl enable system/com.apple.analyticsd",
            statusCommand: "launchctl print-disabled system 2>/dev/null | grep analyticsd",
            appliedWhenOutputContains: "disabled",
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
            category: .network, privilege: .admin, risk: .moderate, sipRequired: false,
            applyCommand: "defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool true; killall -HUP mDNSResponder 2>/dev/null; true",
            revertCommand: "defaults delete /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements 2>/dev/null; killall -HUP mDNSResponder 2>/dev/null; true",
            statusCommand: "defaults read /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements 2>/dev/null",
            appliedWhenOutputContains: "1",
            tags: [.usesAirDropAirPlay, .privacyFocused], recommended: false
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
            tags: [.prioritizePerformance], recommended: false
        ),
        Tweak(
            key: "serverperfmode",
            title: "Server Performance Mode",
            summary: "Biases the scheduler and memory for sustained throughput. Needs SIP off + reboot; replaces boot-args.",
            category: .performance, privilege: .admin, risk: .advanced, sipRequired: true,
            applyCommand: "nvram boot-args=\"serverperfmode=1\"",
            revertCommand: "nvram -d boot-args",
            statusCommand: "nvram boot-args 2>/dev/null | grep -q serverperfmode && echo ON || echo OFF",
            appliedWhenOutputContains: "ON",
            tags: [.prioritizePerformance], recommended: false
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
        // Background services
        "disable-mediaanalysisd": "film",
        "disable-photoanalysisd": "person.crop.rectangle.stack",
        "disable-spotlight": "magnifyingglass",
        // Network
        "mdns-no-advertise": "dot.radiowaves.left.and.right",
        // AI & Intelligence
        "disable-siri-daemon": "mic",
        "disable-lookup-suggestions": "text.magnifyingglass",
        "disable-duetexpertd": "brain",
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
            key: "reindex-spotlight",
            title: "Rebuild Spotlight Index",
            summary: "Erases and rebuilds the Spotlight index for the boot volume.",
            icon: "magnifyingglass", privilege: .admin,
            command: "mdutil -E /", destructive: true
        ),
    ]
}
