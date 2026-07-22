//
//  SystemInfo.swift
//  MacTweak
//
//  Read-only facts about the host, resolved once at launch.
//

import Foundation

enum SystemInfo {

    /// e.g. "Version 26.5.2 (Build 25F84)"
    static let osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString

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

    static let uid: uid_t = getuid()

    static let hostName: String = ProcessInfo.processInfo.hostName

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
}
