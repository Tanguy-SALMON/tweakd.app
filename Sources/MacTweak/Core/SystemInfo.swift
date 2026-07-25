//
//  SystemInfo.swift
//  MacTweak
//
//  Read-only facts about the host, resolved once at launch.
//

import Foundation

enum SystemInfo {

    /// Marketing-ish short version, e.g. "26.5.2"
    static let osShortVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()

    /// System Integrity Protection. Many system-daemon tweaks are inert while this is on.
    static let sipEnabled: Bool = {
        let r = CommandRunner.user("/usr/bin/csrutil status")
        // "System Integrity Protection status: enabled." / "disabled."
        return r.output.localizedCaseInsensitiveContains("enabled")
    }()

    static let physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory

    static let coreCount: Int = ProcessInfo.processInfo.processorCount

    /// Chip / model string via sysctl, best-effort.
    static let chip: String = {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return "Apple Silicon" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        return String(cString: buf)
    }()

    /// Machine identifier, e.g. `Mac14,2` (Apple Silicon) or `MacBookAir10,1`.
    static let modelIdentifier: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }()

    /// P-core / E-core counts on Apple Silicon (`hw.perflevelN`). Both nil on
    /// Intel, which has no heterogeneous cores.
    static let performanceCores: Int? = perflevelCount(0, expecting: "Performance")
    static let efficiencyCores: Int? = perflevelCount(1, expecting: "Efficiency")

    private static func perflevelCount(_ level: Int, expecting name: String) -> Int? {
        // Confirm the level really is the cluster we think it is before trusting
        // its count — Apple orders perflevel0 = fastest, but assert rather than assume.
        var nameSize = 0
        sysctlbyname("hw.perflevel\(level).name", nil, &nameSize, nil, 0)
        guard nameSize > 0 else { return nil }
        var nameBuf = [CChar](repeating: 0, count: nameSize)
        sysctlbyname("hw.perflevel\(level).name", &nameBuf, &nameSize, nil, 0)
        guard String(cString: nameBuf) == name else { return nil }

        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.perflevel\(level).physicalcpu", &count, &size, nil, 0) == 0,
              count > 0 else { return nil }
        return Int(count)
    }

    /// True when this Mac has **no fan**, so sustained load throttles far sooner
    /// than on an actively-cooled model.
    ///
    /// Deliberately a allow-list of known fanless machines rather than a runtime
    /// probe: the obvious probes are unreliable (`ioreg -c AppleSMCFanControl`
    /// matches on fanless Airs too), and guessing wrong in the *other* direction
    /// would hand a Pro user advice meant for an Air. An unrecognised model
    /// therefore reports `false` — "assume it's cooled" is the safe default, and
    /// the UI simply omits the fanless note rather than saying something wrong.
    static let isFanless: Bool = {
        let m = modelIdentifier
        // Intel-era fanless: the 12" MacBook and Retina Airs.
        if m.hasPrefix("MacBookAir") { return true }
        if m.hasPrefix("MacBook") && !m.hasPrefix("MacBookPro") && !m.hasPrefix("MacBookAir") { return true }
        // Apple Silicon Airs (M1 → M4). Mac14,2 / Mac14,15 = M2 13"/15".
        let fanlessAppleSilicon: Set<String> = [
            "MacBookAir10,1",              // M1 Air
            "Mac14,2", "Mac14,15",         // M2 Air 13" / 15"
            "Mac15,12", "Mac15,13",        // M3 Air 13" / 15"
            "Mac16,12", "Mac16,13",        // M4 Air 13" / 15"
        ]
        return fanlessAppleSilicon.contains(m)
    }()
}
