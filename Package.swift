// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DiskWatch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DiskWatch", path: "Sources/DiskWatch")
    ]
)
