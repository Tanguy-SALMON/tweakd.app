//
//  CommandRunner.swift
//  MacTweak
//
//  Shell execution. Two lanes:
//    • user(_:)  — runs as the current user, no prompt.
//    • admin(_:) — runs as root through the native macOS authorization dialog
//                  (osascript `with administrator privileges`). No helper tool,
//                  no deprecated Authorization API, no stored password.
//
//  The command is base64-wrapped before it reaches AppleScript so arbitrary
//  quoting/piping survives without escaping gymnastics.
//

import Foundation

struct CommandResult: Sendable {
    let output: String
    let error: String
    let exitCode: Int32

    var ok: Bool { exitCode == 0 }
    var userCancelled: Bool { error.localizedCaseInsensitiveContains("User canceled") }

    static let cancelled = CommandResult(output: "", error: "User canceled.", exitCode: -128)
}

enum CommandRunner {

    /// Run a command as the current user via `/bin/zsh -c`.
    static func user(_ command: String) -> CommandResult {
        run(executable: "/bin/zsh", arguments: ["-c", command])
    }

    /// Run a command as root through the native authorization prompt.
    static func admin(_ command: String) -> CommandResult {
        let b64 = Data(command.utf8).base64EncodedString()
        // Decoded and piped into zsh entirely inside the privileged shell.
        let inner = "/bin/echo \(b64) | /usr/bin/base64 -D | /bin/zsh"
        let script = "do shell script \"\(inner)\" with administrator privileges"
        let result = run(executable: "/usr/bin/osascript", arguments: ["-e", script])
        return result
    }

    // MARK: - Plumbing

    private static func run(executable: String, arguments: [String]) -> CommandResult {
        let task = Process()
        let out = Pipe()
        let err = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.standardOutput = out
        task.standardError = err

        // Wait via terminationHandler + semaphore instead of waitUntilExit().
        // waitUntilExit() services the calling thread's run loop while waiting,
        // so a synchronous call made during SwiftUI view evaluation re-enters
        // the framework mid-update and triggers "AttributeGraph: cycle detected".
        // A plain blocking wait has identical semantics without the re-entrancy.
        let done = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in done.signal() }

        do {
            try task.run()
        } catch {
            return CommandResult(output: "", error: "launch failed: \(error.localizedDescription)", exitCode: -1)
        }

        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        done.wait()

        return CommandResult(
            output: String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            error: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: task.terminationStatus
        )
    }
}
