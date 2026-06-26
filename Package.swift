// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WaterMark",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WaterMark",
            path: "Sources/WaterMark",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
