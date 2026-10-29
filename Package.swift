// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Dustbuster",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Dustbuster",
            path: "Sources/Dustbuster"
        )
    ]
)
