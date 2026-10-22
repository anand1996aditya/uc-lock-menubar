// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "UCLockMenuBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "UCLockMenuBar",
            path: "Sources/UCLockMenuBar"
        )
    ]
)
