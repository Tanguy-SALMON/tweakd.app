//
//  Log.swift
//  MacTweak
//
//  Lightweight logging so we can actually see what the app did — especially
//  around privilege escalation, which is where things can die. Every line goes
//  to both the unified log (queryable with
//  `log show --predicate 'subsystem == "com.tanguy.MacTweak"'`) and a plain file
//  at ~/Library/Logs/MacTweak/MacTweak.log. A signal/exception handler flushes a
//  final line on a crash — because an OS SIGKILL leaves no .ips behind.
//

import Foundation
import AppKit
import os

enum Log {
    static let subsystem = "com.tanguy.MacTweak"
    private static let logger = Logger(subsystem: subsystem, category: "app")

    /// ~/Library/Logs/MacTweak/MacTweak.log
    static let fileURL: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/MacTweak", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("MacTweak.log")
    }()

    /// A raw append-mode fd kept open for the whole process, so the async-signal
    /// crash handler can write with a bare `write(2)` (no allocation).
    private static let fd: Int32 = {
        open(fileURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    }()

    private static let queue = DispatchQueue(label: subsystem + ".log")

    static func info(_ message: String)  { emit("INFO", message) }
    static func warn(_ message: String)  { emit("WARN", message) }
    static func error(_ message: String) { emit("ERROR", message) }

    private static func emit(_ level: String, _ message: String) {
        logger.log("\(level, privacy: .public) \(message, privacy: .public)")
        let stamp = Self.timestamp()
        queue.async {
            let line = "\(stamp) [\(level)] \(message)\n"
            if let data = line.data(using: .utf8) { data.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) } }
        }
    }

    private static func timestamp() -> String {
        var tv = timeval(); gettimeofday(&tv, nil)
        var t = tv.tv_sec; var tmv = tm(); localtime_r(&t, &tmv)
        // Every `%d` arg must be a 32-bit CInt to match the varargs ABI — the tm_*
        // fields already are; the microseconds must be narrowed explicitly.
        return String(format: "%04d-%02d-%02d %02d:%02d:%02d.%03d",
                      tmv.tm_year + 1900, tmv.tm_mon + 1, tmv.tm_mday,
                      tmv.tm_hour, tmv.tm_min, tmv.tm_sec, Int32(tv.tv_usec / 1000))
    }

    /// Preformatted crash line, built once at install so the signal handler does
    /// nothing but a bare `write(2)` — no malloc, no String, no lazy init (all of
    /// which are async-signal-unsafe). The signal number is recovered from the OS
    /// crash report produced by the re-raise below, so we don't format it here.
    private static let crashLine = Array("\n*** MacTweak: fatal signal — aborting (see crash report) ***\n".utf8)

    /// Install once at launch: log the session banner + crash catchers.
    static func installCrashHandlers() {
        // Force the lazy `fd` (and its log-directory creation) open NOW, on the
        // calling thread — so the async-signal-safe handler below can never trip
        // `swift_once`/`FileManager` from inside a crash.
        _ = fd
        _ = crashLine
        info("——— MacTweak launched (v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")) pid \(getpid()) ———")

        // Obj-C exceptions aren't delivered in signal context, so String/allocation is safe here.
        NSSetUncaughtExceptionHandler { exc in
            Log.emit("CRASH", "uncaught \(exc.name.rawValue): \(exc.reason ?? "")")
            Log.emit("CRASH", exc.callStackSymbols.joined(separator: " | "))
        }
        for sig in [SIGILL, SIGABRT, SIGSEGV, SIGBUS, SIGTRAP, SIGFPE] {
            signal(sig) { s in
                // Async-signal-safe: only a bare write of the preallocated line.
                Log.crashLine.withUnsafeBytes { _ = write(Log.fd, $0.baseAddress, $0.count) }
                signal(s, SIG_DFL); raise(s)
            }
        }

        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: nil) { _ in
            Log.info("app willTerminate (clean)")
        }
    }
}
