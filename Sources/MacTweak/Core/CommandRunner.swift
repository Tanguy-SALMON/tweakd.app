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

    static let sudoersPath = "/etc/sudoers.d/mactweak"

    /// True when the sudoers rule is in place, so `sudo -n` needs no password.
    static func hasPasswordlessAdmin() -> Bool {
        run(executable: "/usr/bin/sudo", arguments: ["-n", "/bin/zsh", "-c", "true"]).exitCode == 0
    }

    /// One-time: prompt for the password once and install the sudoers rule so
    /// every later admin command runs without a prompt.
    static func enablePasswordlessAdmin() -> CommandResult {
        let user = NSUserName()
        let install = """
        f=\(sudoersPath)
        /usr/bin/printf '%s\\n' \
          '# MacTweak — apply admin tweaks without re-entering your password.' \
          '# Delete this file (or use MacTweak > Lock Admin) to revoke.' \
          '\(user) ALL=(root) NOPASSWD: /bin/zsh' > "$f"
        /bin/chmod 0440 "$f"
        /usr/sbin/chown root:wheel "$f"
        if ! /usr/sbin/visudo -cf "$f" >/dev/null 2>&1; then /bin/rm -f "$f"; echo INVALID; exit 1; fi
        echo OK
        """
        return adminPrompt(install)
    }

    /// Remove the sudoers rule — admin commands prompt again afterwards.
    static func disablePasswordlessAdmin() -> CommandResult {
        let remove = "/bin/rm -f \(sudoersPath)"
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
        let errDrain = DispatchQueue(label: "com.tanguy.MacTweak.cmd.stderr")
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
