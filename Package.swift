// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Taskport",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Taskport", targets: ["Taskport"]),
               .executable(name: "taskport-cli", targets: ["TaskportCLI"])],
    dependencies: [
        .package(url: "https://github.com/Lakr233/libghostty-spm.git", exact: "1.6.20260909")
    ],
    targets: [
        .target(name: "TaskportPTY"),
        .target(name: "TaskportControl"),
        .executableTarget(name: "TaskportCLI", dependencies: ["TaskportControl"]),
        .executableTarget(
            name: "Taskport",
            dependencies: ["TaskportPTY", "TaskportControl", .product(name: "GhosttyTerminal", package: "libghostty-spm")]
        ),
        .testTarget(name: "TaskportTests", dependencies: ["Taskport", "TaskportPTY", "TaskportControl"])
    ]
)
