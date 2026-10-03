// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UnraidWatcher",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "UnraidWatcher", path: "Sources/UnraidWatcher")
    ]
)
