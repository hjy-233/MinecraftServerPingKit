// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MinecraftServerPingKit",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MinecraftServerPingKit",
            targets: ["MinecraftServerPingKit"],
        ),
    ],
    targets: [
        .target(name: "MinecraftServerPingKit"),
        .testTarget(
            name: "MinecraftServerPingKitTests",
            dependencies: ["MinecraftServerPingKit"],
        ),
    ],
)
