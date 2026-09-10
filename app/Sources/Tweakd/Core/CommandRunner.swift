//
//  CommandRunner.swift
//  tweakd
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

    /// Run a command as root. Passwordless once admin is unlocked; otherwise
    /// falls back to a one-off native authorization prompt.
    static func admin(_ command: String) -> CommandResult {
        let passwordless = hasPasswordlessAdmin()
        Log.info("admin start (\(passwordless ? "sudo -n" : "osascript prompt")): \(command.prefix(80))")
        let r = passwordless ? adminNoPrompt(command) : adminPrompt(command)
        Log.info("admin done exit=\(r.exitCode) out=\(r.output.prefix(60)) err=\(r.error.prefix(120))")
        return r
    }

    // MARK: - Passwordless admin (one-time unlock)

    static let sudoersPath = Brand.sudoersPath

    /// True when the sudoers rule is in place, so `sudo -n` needs no password.
    ///
    /// Deliberately tests the *capability* rather than the file, so it stays
    /// correct regardless of which name installed the rule.
    static func hasPasswordlessAdmin() -> Bool {
        run(executable: "/usr/bin/sudo", arguments: ["-n", "/bin/zsh", "-c", "true"]).exitCode == 0
    }

    /// One-time: prompt for the password once and install the sudoers rule so
    /// every later admin command runs without a prompt.
    static func enablePasswordlessAdmin() -> CommandResult {
        let user = NSUserName()
        // Clear the pre-rename rule in the same pass, so unlocking can't leave two
        // drop-ins granting the same thing under different names.
        let install = """
        /bin/rm -f \(Brand.legacySudoersPath)
        f=\(sudoersPath)
        /usr/bin/printf '%s\\n' \
          '# \(Brand.name) — apply admin tweaks without re-entering your password.' \
          '# Delete this file (or use \(Brand.name) > Lock Admin) to revoke.' \
          '\(user) ALL=(root) NOPASSWD: /bin/zsh' > "$f"
        /bin/chmod 0440 "$f"
        /usr/sbin/chown root:wheel "$f"
        if ! /usr/sbin/visudo -cf "$f" >/dev/null 2>&1; then /bin/rm -f "$f"; echo INVALID; exit 1; fi
        echo OK
        """
        return adminPrompt(install)
    }

    /// Remove the sudoers rule — admin commands prompt again afterwards.
    ///
    /// Removes **every** path this app has ever written. Missing the legacy one
    /// would be the worst kind of bug here: Lock would report success while the
    /// old drop-in kept granting passwordless root indefinitely.
    static func disablePasswordlessAdmin() -> CommandResult {
        let remove = Brand.allSudoersPaths.map { "/bin/rm -f \($0)" }.joined(separator: "; ")
        return hasPasswordlessAdmin() ? adminNoPrompt(remove) : adminPrompt(remove)
    }

    // MARK: - Escalation backends

    /// Base64-wrap a command so arbitrary quoting/piping survives, decoded and
    /// run inside the privileged shell. Keeps the escalation encoding in one place.
    private static func zshPipeline(_ command: String) -> String {
        let b64 = Data(command.utf8).base64EncodedString()
        return "/bin/echo \(b64) | /usr/bin/base64 -D | /bin/zsh"
    }

    /// Root via `sudo -n` (no prompt). Requires the sudoers rule.
    private static func adminNoPrompt(_ command: String) -> CommandResult {
        run(executable: "/usr/bin/sudo",
            arguments: ["-n", "/bin/zsh", "-c", zshPipeline(command)])
    }

    /// Root via the native authorization dialog (one password prompt).
    private static func adminPrompt(_ command: String) -> CommandResult {
        let script = "do shell script \"\(zshPipeline(command))\" with administrator privileges"
        let result = run(executable: "/usr/bin/osascript", arguments: ["-e", script])
        // The auth dialog steals focus; for a menu-bar (accessory) app the window
        // drops behind everything and looks like a crash. Centralised here — the
        // ONE place the dialog is shown — so no call site can forget to recover.
        TweakEngine.reactivate()
        return result
    }

    // MARK: - Long-running admin stream

    /// A privileged process left running, delivering stdout a line at a time.
    /// Cancel it by calling `stop()` or simply dropping the handle.
    final class StreamHandle: @unchecked Sendable {
        private let task: Process
        private let pipe: Pipe
        private var stopped = false

        init(task: Process, pipe: Pipe) {
            self.task = task
            self.pipe = pipe
        }

        func stop() {
            guard !stopped else { return }
            stopped = true
            pipe.fileHandleForReading.readabilityHandler = nil
            // Terminating `sudo` does NOT reap its child, so the sampler would
            // otherwise keep running as root forever. Closing our end of the pipe
            // is what actually kills it: the child gets SIGPIPE on its next write,
            // which for a 1 Hz sampler is within a second.
            try? pipe.fileHandleForReading.close()
            if task.isRunning { task.terminate() }
        }

        deinit { stop() }
    }

    /// Start a privileged command and stream its stdout line by line.
    ///
    /// Returns nil unless admin is already unlocked. There is deliberately no
    /// prompting fallback: `osascript … with administrator privileges` only
    /// hands back output once the command *finishes*, so a continuous sampler
    /// under it would stream nothing and never end.
    ///
    /// The caller is responsible for bounding the command's lifetime — anything
    /// started here is root, and a UI that forgets to stop it leaves it running.
    static func streamAdmin(_ command: String,
                            onLine: @escaping @Sendable (String) -> Void,
                            onEnd: @escaping @Sendable () -> Void = {}) -> StreamHandle? {
        guard hasPasswordlessAdmin() else { return nil }
        Log.info("admin stream start: \(command.prefix(80))")

        let task = Process()
        let out = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", "/bin/zsh", "-c", zshPipeline(command)]
        task.standardOutput = out
        task.standardError = FileHandle.nullDevice

        // Reassembled here rather than per-read: a pipe read boundary lands
        // mid-line often enough that parsing raw chunks silently drops samples.
        let buffer = LineBuffer()
        out.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            for line in buffer.feed(data) { onLine(line) }
        }
        task.terminationHandler = { _ in
            Log.info("admin stream ended")
            onEnd()
        }

        do {
            try task.run()
        } catch {
            Log.error("admin stream launch failed: \(error.localizedDescription)")
            return nil
        }
        return StreamHandle(task: task, pipe: out)
    }

    /// Accumulates pipe chunks and hands back only whole lines.
    private final class LineBuffer: @unchecked Sendable {
        private var partial = ""
        private let lock = NSLock()

        func feed(_ data: Data) -> [String] {
            lock.lock(); defer { lock.unlock() }
            partial += String(decoding: data, as: UTF8.self)
            var lines = partial.components(separatedBy: "\n")
            partial = lines.removeLast()   // trailing fragment waits for more
            return lines
        }
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
            Log.error("process launch failed \(executable): \(error.localizedDescription)")
            return CommandResult(output: "", error: "launch failed: \(error.localizedDescription)", exitCode: -1)
        }

        // Drain both pipes concurrently. Reading stdout to EOF *before* touching
        // stderr deadlocks any command that fills the 64 KB stderr pipe buffer
        // before closing stdout (it blocks on write() while we block on read()).
        var errData = Data()
        let errDrain = DispatchQueue(label: "app.tweakd.cmd.stderr")
        errDrain.async { errData = err.fileHandleForReading.readDataToEndOfFile() }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        errDrain.sync {}          // barrier: stderr fully read
        done.wait()

        return CommandResult(
            output: String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            error: String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            exitCode: task.terminationStatus
        )
    }
}
