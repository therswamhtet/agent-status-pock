// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AgentBridge",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "AgentBridge",
            path: "Sources/AgentBridge"
        )
    ]
)
