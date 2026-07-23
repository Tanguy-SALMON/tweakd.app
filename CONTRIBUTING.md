# Contributing to MacTweak

MacTweak is data-driven: the catalog is the source of truth, and adding a tweak is a
one-entry change. This guide covers how to build, add a tweak safely, and the
conventions the code follows.

## Build & run

Requirements: **macOS 15+**, **Xcode 16+** (Swift 6 / Swift Charts).

```bash
# compile, bundle into build/MacTweak.app, and launch (default)
Scripts/build.sh

# build + bundle without launching
Scripts/build.sh --no-launch

# debug build
Scripts/build.sh --debug

# all flags
Scripts/build.sh --help
```

The script kills any running instance, compiles the `.icns` from
`Resources/AppIcon.iconset`, generates the `Info.plist` (stamping `CFBundleVersion`
with the short git commit), ad-hoc signs with `MacTweak.entitlements`, and hides the
`.app` extension in Finder.

You can also `open Package.swift` in Xcode and Run — but the bare SPM executable skips
the `Info.plist`, so use the script for the real menu-bar experience.

## Adding a tweak

Add one entry to `TweakCatalog.all` in `Sources/MacTweak/Models/TweakCatalog.swift`:

```swift
Tweak(
    key: "my-tweak",                    // unique, kebab-case
    title: "Human Title",
    summary: "One line of what it does (and any trade-off).",
    category: .performance,             // TweakCategory
    privilege: .admin,                  // .user (no prompt) | .admin (root)
    risk: .safe,                        // .safe | .moderate | .advanced
    sipRequired: false,                 // true → Unavailable while SIP is on
    applyCommand:  "sysctl -w some.knob=0",
    revertCommand: "sysctl -w some.knob=1",
    statusCommand: "sysctl -n some.knob",
    appliedWhenOutputContains: "0",     // stdout contains this ⇒ shown as Applied
    tags: [.prioritizePerformance], recommended: true
)
```

Give it a distinct SF Symbol in `TweakCatalog.iconOverrides`
(`"my-tweak": "sparkles"`); it falls back to the category glyph otherwise.

### Rules of thumb (learned the hard way)

- **`appliedWhenOutputContains` is a case-insensitive substring test.** Make the
  marker **unambiguous**. Matching `"0"` or `"2"` is dangerous — those substrings
  appear inside unrelated values (`12`, `20`, `120`). When the value is numeric or
  multi-valued, have `statusCommand` emit a distinct token instead:
  ```bash
  test "$(defaults read -g KeyRepeat 2>/dev/null)" = 2 && echo APPLIED
  # appliedWhenOutputContains: "APPLIED"
  ```
- **`revertCommand` must truly undo `applyCommand`.** Prefer `defaults delete` (restores
  the macOS default) over writing a guessed value. Keep the apply/revert/status sets in
  sync — if you add a browser/key to apply, add it to revert **and** status.
- **Reversibility is mandatory.** No tweak ships without a working revert.
- **Verify against real output.** Run the `statusCommand` before/after on a real Mac.
  The catalog header says it plainly: commands are verified against macOS output — the
  app rejects toggles that reference sysctls/keys that don't exist.
- **`sudo` is added automatically** for `.admin` tweaks (the app escalates via the
  native dialog or `sudo -n`). Write the command *without* `sudo` in the catalog.
- **User-agent `launchctl`** uses the `gui/$(id -u)` domain (there's a `private static
  let g = "gui/$(id -u)"` helper). System daemons use `system/…` and are `sipRequired`.
- **`; true`** at the end of a command forces exit 0 for cleanup steps that may legitimately
  return non-zero (e.g. `defaults delete` on an absent key, `killall` on an absent process).

### If a tweak needs a one-shot, not a toggle

Add a `SystemAction` to `TweakCatalog.actions` instead (purge, flush DNS, restart a
daemon…). Same command style; no `revert`/`status`.

## Conventions

- **Everything routes through `CommandRunner`** — never build your own `Process`. Use
  `CommandRunner.user` / `.admin`; they handle escalation, pipe draining, and the
  non-`waitUntilExit` wait that avoids SwiftUI re-entrancy. See
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- **Colors come from `Theme`** — `Theme.accent`, `Theme.accentDeep`,
  `Theme.accentGradient`. No hardcoded oranges.
- **Icons/tiles use `GlyphTile`**, buttons use `.buttonStyle(.gradient)` /
  `.gradientOutline`.
- **State lives on `@MainActor` objects** owned by `AppModel`; mutate `@Published`
  fields on the main actor, do blocking work in `Task.detached`.
- **Match the surrounding style** — comment density, naming, and idiom.

## Documentation

When you add a tweak, mirror it in:
- [`docs/TWEAKS.md`](docs/TWEAKS.md) — the manual apply/revert reference.
- [`docs/index.html`](docs/index.html) — the web docs (same content, copy buttons).
- [`README.md`](README.md) — bump the tweak count if you cite it.

## Reviewing changes

- `/code-review` for correctness; `/simplify` for cleanup. The high-signal risk areas
  are the **shell command strings** (quoting, `appliedWhenOutputContains` ambiguity,
  apply/revert asymmetry) and **concurrency** (main-actor isolation, pipe draining).
