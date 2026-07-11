// swift-tools-version:5.10
// SwiftX - ShareX for macOS (GPL v3), see /LICENSE.txt

import PackageDescription

let package = Package(
    name: "SwiftX",
    platforms: [.macOS(.v14)], // SCScreenshotManager baseline
    products: [
        .executable(name: "swiftx", targets: ["SwiftXApp"]),
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
        .target(
            name: "UploadKit",
            dependencies: ["SharedKit"]
        ),
        .target(
            name: "HistoryKit",
            dependencies: ["SharedKit"]
        ),
        .target(
            name: "EditorKit"
        ),
        .target(
            name: "ToolsKit",
            dependencies: ["CaptureKit"]
        ),
        .executableTarget(
            name: "SwiftXApp",
            dependencies: ["SharedKit", "CaptureKit", "UploadKit", "HistoryKit", "EditorKit", "ToolsKit"]
        ),
        .testTarget(
            name: "SharedKitTests",
            dependencies: ["SharedKit"]
        ),
        .testTarget(
            name: "CaptureKitTests",
            dependencies: ["CaptureKit"]
        ),
        .testTarget(
            name: "UploadKitTests",
            dependencies: ["UploadKit"]
        ),
        .testTarget(
            name: "HistoryKitTests",
            dependencies: ["HistoryKit"]
        ),
        .testTarget(
            name: "EditorKitTests",
            dependencies: ["EditorKit"]
        ),
        .testTarget(
            name: "ToolsKitTests",
            dependencies: ["ToolsKit", "CaptureKit"]
        )
    ]
)
