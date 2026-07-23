# Product Requirement Prompts (PRP): MacTweak "Core Audio Repair" Feature

## Overview

Add a **beta** feature to MacTweak that diagnoses and fixes common `coreaudiod` high‑CPU issues. This feature will:

1. Detect if the `~/Library/Preferences/Audio` folder is missing and create it with correct ownership.
2. Optionally restart `coreaudiod` (with user consent and sudo).
3. Optionally kill any misbehaving audio‑related processes (like `64_coreaudio`) that are consuming excessive CPU.

The feature will be placed in a new **“Audio & System Services”** category, with a prominent beta warning.

---

## PRP Structure

- **Phase 1**: Extend data model to support “action” tweaks (not just toggles).
- **Phase 2**: Implement `CoreAudioRepairManager` – the logic for detection, repair, and verification.
- **Phase 3**: Design UI for repair flow (diagnostic button + optional toggles).
- **Phase 4**: Integrate with existing `TweakManager` and `ShellExecutor`.
- **Phase 5**: Add beta disclaimer and emergency revert notes.

---

## Phase 1: Extend Data Model

### Step 1.1: Add New Tweak Type

In `Tweak.swift`, extend the model to support **action** tweaks (buttons) in addition to simple toggles.

```swift
enum TweakType {
    case toggle          // on/off switch
    case action          // one‑time button that runs a repair
    case diagnostic      // displays status, no modification
}

struct Tweak: Identifiable {
    let id = UUID()
    let key: String
    let name: String
    let description: String
    let category: TweakCategory
    let type: TweakType
    let requiresSudo: Bool
    var command: String?          // for toggle/action
    var reverseCommand: String?   // for toggle only
    var checkCommand: String?     // for toggle only
    var isEnabled: Bool = false   // for toggle only
    var isBeta: Bool = false
    var actionTitle: String?      // button label if type == .action
}
```

### Step 1.2: Add New Category

```swift
enum TweakCategory: String, CaseIterable {
    case performance = "Performance"
    case privacy = "Privacy"
    case systemServices = "System Services"
    case powerManagement = "Power Management"
    case network = "Network"
    case ai = "AI & Intelligence"
    case audio = "Audio & System"   // new
}
```

---

## Phase 2: CoreAudioRepairManager

### Step 2.1: Create Manager Class

```swift
import Foundation

class CoreAudioRepairManager: ObservableObject {
    @Published var statusMessage: String = "Ready"
    @Published var isRunning: Bool = false
    @Published var lastError: String?
    
    // MARK: - Diagnostic
    func diagnose() -> [String: Any] {
        var results: [String: Any] = [:]
        
        // Check if Preferences/Audio exists
        let audioPrefsPath = NSHomeDirectory() + "/Library/Preferences/Audio"
        let fm = FileManager.default
        results["audioPrefsExists"] = fm.fileExists(atPath: audioPrefsPath)
        
        // Check coreaudiod CPU usage
        let cpuOutput = ShellExecutor.execute("ps -p $(pgrep coreaudiod) -o pcpu= 2>/dev/null | tr -d ' '")
        if let cpu = Double(cpuOutput.output.trimmingCharacters(in: .whitespacesAndNewlines)) {
            results["coreaudiodCPU"] = cpu
        } else {
            results["coreaudiodCPU"] = -1
        }
        
        // Check for rogue audio processes (e.g., 64_coreaudio)
        let rogueOutput = ShellExecutor.execute("ps aux | grep -E '64_coreaudio|python.*coreaudio' | grep -v grep")
        results["rogueProcesses"] = rogueOutput.output.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return results
    }
    
    // MARK: - Repair Actions
    func createAudioPrefsFolder() -> Bool {
        let audioPrefsPath = NSHomeDirectory() + "/Library/Preferences/Audio"
        let fm = FileManager.default
        if fm.fileExists(atPath: audioPrefsPath) {
            statusMessage = "Audio preferences folder already exists."
            return true
        }
        do {
            try fm.createDirectory(atPath: audioPrefsPath, withIntermediateDirectories: true, attributes: nil)
            // Set ownership to _coreaudiod:admin (requires sudo)
            let chownResult = ShellExecutor.execute("sudo chown _coreaudiod:admin \"\(audioPrefsPath)\"")
            if chownResult.exitCode == 0 {
                statusMessage = "Audio preferences folder created."
                return true
            } else {
                statusMessage = "Folder created but could not set ownership (sudo may be required)."
                return false
            }
        } catch {
            statusMessage = "Failed to create folder: \(error.localizedDescription)"
            lastError = error.localizedDescription
            return false
        }
    }
    
    func restartCoreAudio() -> Bool {
        let result = ShellExecutor.execute("sudo killall coreaudiod 2>/dev/null")
        if result.exitCode == 0 {
            statusMessage = "coreaudiod restarted successfully."
            return true
        } else {
            statusMessage = "Failed to restart coreaudiod. Make sure you have admin privileges."
            lastError = result.error
            return false
        }
    }
    
    func killRogueAudioProcesses() -> Bool {
        let roguePatterns = ["64_coreaudio", "python.*coreaudio"]
        var success = true
        for pattern in roguePatterns {
            let killResult = ShellExecutor.execute("sudo pkill -f \"\(pattern)\" 2>/dev/null")
            if killResult.exitCode != 0 && !killResult.output.contains("no process found") {
                success = false
                statusMessage = "Could not kill processes matching '\(pattern)'."
                lastError = killResult.error
            }
        }
        if success {
            statusMessage = "Rogue audio processes terminated."
        }
        return success
    }
    
    func runFullRepair() -> (Bool, String) {
        isRunning = true
        defer { isRunning = false }
        
        var steps: [String] = []
        var allOK = true
        
        // Step 1: Create folder
        if createAudioPrefsFolder() {
            steps.append("✅ Audio preferences folder verified/created.")
        } else {
            steps.append("⚠️ Could not create audio preferences folder.")
            allOK = false
        }
        
        // Step 2: Restart coreaudiod
        if restartCoreAudio() {
            steps.append("✅ coreaudiod restarted.")
        } else {
            steps.append("⚠️ Could not restart coreaudiod (sudo required).")
            allOK = false
        }
        
        // Step 3: Kill rogue processes
        if killRogueAudioProcesses() {
            steps.append("✅ Rogue audio processes killed.")
        } else {
            steps.append("⚠️ Could not kill all rogue processes.")
            allOK = false
        }
        
        // Final message
        let finalMsg = steps.joined(separator: "\n")
        return (allOK, finalMsg)
    }
}
```

### Step 2.2: Extend TweakManager

Add a property to hold the repair manager and integrate it.

```swift
class TweakManager: ObservableObject {
    // ...
    let coreAudioRepair = CoreAudioRepairManager()
    
    // Add a new tweak definition for the repair action
    func loadTweaks() {
        // ... existing tweaks ...
        
        let audioRepairTweak = Tweak(
            key: "coreaudiorepair",
            name: "Repair Core Audio CPU",
            description: "Fix common coreaudiod high-CPU issues (beta).",
            category: .audio,
            type: .action,
            requiresSudo: true,
            command: nil,
            reverseCommand: nil,
            checkCommand: nil,
            isBeta: true,
            actionTitle: "Run Repair"
        )
        tweaks.append(audioRepairTweak)
    }
    
    func performAction(for tweak: Tweak) {
        guard tweak.type == .action else { return }
        switch tweak.key {
        case "coreaudiorepair":
            coreAudioRepair.runFullRepair()
        default:
            break
        }
    }
}
```

---

## Phase 3: UI Design

### Step 3.1: New Category View

In `MainView`, the `audio` category will appear. When selected, show a list of tweaks in that category, including the action tweak.

### Step 3.2: Action Tweak Row

Create a new view `ActionTweakRow` for action tweaks.

```swift
struct ActionTweakRow: View {
    let tweak: Tweak
    let onAction: () -> Void
    
    @State private var showingBetaWarning = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text(tweak.name)
                            .font(.headline)
                        if tweak.isBeta {
                            Text("BETA")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    Text(tweak.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(tweak.actionTitle ?? "Run") {
                    if tweak.isBeta {
                        showingBetaWarning = true
                    } else {
                        onAction()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(tweak.isBeta && !showingBetaWarning)
            }
            if tweak.requiresSudo {
                Label("Requires administrator password", systemImage: "lock.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 6)
        .alert("Beta Feature Warning", isPresented: $showingBetaWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Run Anyway", role: .destructive) {
                onAction()
            }
        } message: {
            Text("""
            This action is experimental and may:
            
            • Require a system restart
            • Cause audio issues temporarily
            • Have no effect on some systems
            
            Continue only if you understand the risks.
            """)
        }
    }
}
```

### Step 3.3: Show Diagnostic Information

After the repair action runs, display a status sheet or inline results.

```swift
@State private var repairResult: String?
@State private var showResultSheet = false

// Inside the view
.onReceive(coreAudioRepair.$statusMessage) { msg in
    if !msg.isEmpty {
        repairResult = msg
        showResultSheet = true
    }
}
.sheet(isPresented: $showResultSheet) {
    RepairResultView(result: repairResult ?? "No result")
}
```

---

## Phase 4: ShellExecutor Enhancements

Ensure `ShellExecutor` can handle sudo commands properly. Since the app will prompt for password via macOS authorization, we can use `AuthorizationExecuteWithPrivileges` (deprecated) or use `Process` with `launchctl` for user-level and `osascript` for admin. For simplicity, we can rely on the user to run the app with admin privileges or use `sudo` inside the command and let the system prompt for password (if running in Terminal). However, for a GUI app, we should use the `Authorization` framework.

**For this PRP, we’ll keep it simple:** The app will attempt to run `sudo` commands and if they fail, it will display a message asking the user to run the script manually or grant admin permissions via System Preferences.

We can add a method in `TweakManager` to check for admin rights and guide the user.

---

## Phase 5: Beta Disclaimer and Revert

### Step 5.1: In-app Disclaimer

Add a warning banner in the Audio category view:

```swift
Text("⚠️ This feature is in beta. It may not work on all systems and may require a system restart if audio issues persist.")
    .font(.footnote)
    .foregroundColor(.orange)
    .padding()
```

### Step 5.2: Emergency Revert Script

Generate a revert script that the user can run if the repair causes issues. The script should undo the folder creation (optional, but we can include a `rm -rf ~/Library/Preferences/Audio` if needed) and restart coreaudiod.

```bash
#!/bin/bash
# MacTweak Core Audio Emergency Revert
echo "Reverting core audio changes..."
# Remove the created folder
rm -rf ~/Library/Preferences/Audio
# Restart coreaudiod
sudo killall coreaudiod
echo "Revert complete. Audio system restarted."
```

We can save this script to `~/Documents/MacTweak_Audio_Revert.sh` and make it executable.

---

## Phase 6: Testing

Test the feature under these conditions:

1. **Missing Audio folder** – verify creation and ownership.
2. **High coreaudiod CPU** – verify restart reduces CPU.
3. **Rogue Python audio process** – verify it’s killed.
4. **Beta warning** – ensure user is prompted before running.
5. **Sudo failure** – handle gracefully with error message.
6. **Revert script** – test that it removes folder and restarts audio.

---

## Deliverables

The AI should produce:

- Updated `Tweak.swift` with new types.
- `CoreAudioRepairManager.swift` with full logic.
- Updates to `TweakManager.swift` to include the new tweak and action handling.
- New UI views: `ActionTweakRow`, `RepairResultView`.
- Updated `MainView` to support the audio category.
- Emergency revert script generation in `TweakManager` (optional).
- Updated `Info.plist` (if needed) to request admin privileges (not required for this PRP).

---

## Next Steps

This PRP can be handed to an AI coding assistant to implement the feature step‑by‑step. Once implemented, the app will have a one‑click repair for coreaudiod issues, dramatically improving user experience.

---

**Would you like me to elaborate on any specific phase or provide the complete code for any component?**
