// swift-tools-version:5.10
// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import PackageDescription

let package = Package(
    name: "SwiftX",
    platforms: [.macOS(.v14)], // SCScreenshotManager baseline
    products: [
        .executable(name: "swiftx", targets: ["SwiftXApp"]),
        .executable(name: "swiftx-host", targets: ["NativeMessagingHost"]),
        // Binary inside SwiftXShare.appex; make-app.sh wraps it in the bundle.
        .executable(name: "swiftx-share", targets: ["ShareExtension"]),
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
            name: "EffectsKit"
        ),
        .target(
            name: "ToolsKit",
            dependencies: ["CaptureKit"]
        ),
        .executableTarget(
            name: "NativeMessagingHost"
        ),
        .executableTarget(
            name: "ShareExtension",
            dependencies: ["SharedKit"]
        ),
        .executableTarget(
            name: "SwiftXApp",
            dependencies: ["SharedKit", "CaptureKit", "UploadKit", "HistoryKit", "EditorKit", "EffectsKit", "ToolsKit"]
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
            name: "EffectsKitTests",
            dependencies: ["EffectsKit"]
        ),
        .testTarget(
            name: "ToolsKitTests",
            dependencies: ["ToolsKit", "CaptureKit"]
        )
    ]
)
