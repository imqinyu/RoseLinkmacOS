// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RoseLink",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "RoseLink",
            path: "Sources/RoseLink"
        )
    ]
)
