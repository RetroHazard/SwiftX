// swift-tools-version:5.10
// ShareX for macOS - part of ShareX (GPL v3), see /LICENSE.txt

import PackageDescription

let package = Package(
    name: "ShareX",
    platforms: [.macOS(.v14)], // SCScreenshotManager baseline
    products: [
        .executable(name: "sharex", targets: ["ShareXApp"]),
        .library(name: "SharedKit", targets: ["SharedKit"]),
        .library(name: "CaptureKit", targets: ["CaptureKit"])
    ],
    targets: [
        .target(
            name: "SharedKit",
            resources: [.process("Resources")]
        ),
        .target(
            name: "CaptureKit"
        ),
        .executableTarget(
            name: "ShareXApp",
            dependencies: ["SharedKit", "CaptureKit"]
        ),
        .testTarget(
            name: "SharedKitTests",
            dependencies: ["SharedKit"]
        ),
        .testTarget(
            name: "CaptureKitTests",
            dependencies: ["CaptureKit"]
        )
    ]
)
