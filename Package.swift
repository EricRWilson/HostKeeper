// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HostKeeper",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Automatic updates. Pinned exactly so every build ships the same updater.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .target(name: "SSHConfigKit"),
        .executableTarget(
            name: "HostKeeper",
            dependencies: ["SSHConfigKit", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "HostKeeperTests", dependencies: ["SSHConfigKit"]),
    ]
)
