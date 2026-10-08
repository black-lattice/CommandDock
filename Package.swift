// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CommandDock",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CommandDock", targets: ["CommandDock"])],
    targets: [
        .target(name: "CommandDockCore"),
        .executableTarget(name: "CommandDock", dependencies: ["CommandDockCore"]),
        .testTarget(name: "CommandDockCoreTests", dependencies: ["CommandDockCore"])
    ]
)
