// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Taskport",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Taskport", targets: ["Taskport"]),
               .executable(name: "taskport-cli", targets: ["TaskportCLI"])],
    dependencies: [
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", exact: "1.6.20260909"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.9.6")
    ],
    targets: [
        .target(name: "TaskportPTY"),
        .target(name: "TaskportControl"),
        .executableTarget(name: "TaskportCLI", dependencies: ["TaskportControl"]),
        .executableTarget(
            name: "Taskport",
            dependencies: ["TaskportPTY", "TaskportControl", .product(name: "GhosttyTerminal", package: "libghostty-spm"),
                           .product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(name: "TaskportTests", dependencies: ["Taskport", "TaskportPTY", "TaskportControl"])
    ]
)
