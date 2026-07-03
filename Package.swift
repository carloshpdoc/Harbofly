// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Harbofly",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Harbofly", path: "Sources/Harbofly")
    ]
)
