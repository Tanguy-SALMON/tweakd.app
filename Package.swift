// swift-tools-version:6.0
import PackageDescription

// The Swift module is `Tweakd` (capitalized, per Swift convention); everything
// user-visible — the app bundle, the menu-bar item, the docs — is lowercase
// `tweakd`, matching the domain tweakd.app.
let package = Package(
    name: "Tweakd",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "Tweakd",
            path: "Sources/Tweakd",
            swiftSettings: [
                // Pragmatic concurrency for a single-user desktop app.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
