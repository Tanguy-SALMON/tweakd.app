// swift-tools-version:6.0
import PackageDescription

// The Swift module is `Tweakd`, per Swift convention. The brand reads "Tweakd"
// everywhere the user sees it (see `Brand.displayName`), while the bundle
// filename, executable and every on-disk path stay lowercase `tweakd` —
// matching the domain tweakd.app, and matching the artifacts already on disk
// under that name (see `Brand.name`).
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
