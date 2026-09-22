// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "Gharwale",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Gharwale",
            path: "Sources/Gharwale"
        )
    ]
)
