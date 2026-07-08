// swift-tools-version:5.10
// ShareX for macOS - part of ShareX (GPL v3), see /LICENSE.txt

import PackageDescription

let package = Package(
    name: "ShareX",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "sharex", targets: ["ShareXApp"]),
        .library(name: "SharedKit", targets: ["SharedKit"])
    ],
    targets: [
        .target(
            name: "SharedKit",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "ShareXApp",
            dependencies: ["SharedKit"]
        ),
        .testTarget(
            name: "SharedKitTests",
            dependencies: ["SharedKit"]
        )
    ]
)
