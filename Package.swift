// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MacTweak",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "MacTweak",
            path: "Sources/MacTweak",
            swiftSettings: [
                // Pragmatic concurrency for a single-user desktop app.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
