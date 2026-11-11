// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HostKeeper",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SSHConfigKit"),
        .executableTarget(name: "HostKeeper", dependencies: ["SSHConfigKit"]),
        .testTarget(name: "HostKeeperTests", dependencies: ["SSHConfigKit"]),
    ]
)
