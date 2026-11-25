// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CommandDock",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "CommandDock", targets: ["CommandDock"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(name: "CommandDockCore"),
        .executableTarget(name: "CommandDock", dependencies: [
            "CommandDockCore", .product(name: "Sparkle", package: "Sparkle")
        ]),
        .testTarget(name: "CommandDockCoreTests", dependencies: ["CommandDockCore"]),
        .testTarget(name: "CommandDockTests", dependencies: ["CommandDock", "CommandDockCore"])
    ]
)
