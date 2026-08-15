// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SuperGit",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SuperGit",
            path: "Sources/SuperGit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
