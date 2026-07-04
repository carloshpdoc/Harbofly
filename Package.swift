// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Harbofly",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Harbofly",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "TelemetryDeck", package: "SwiftSDK"),
            ],
            path: "Sources/Harbofly"
        )
    ]
)
