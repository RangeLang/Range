// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RangeGenerated",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "RangeGenerated"
        )
    ]
)