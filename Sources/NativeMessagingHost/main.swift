// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Browser native messaging host (C# ShareX.NativeMessagingHost). The browser
// launches this with the extension origin as an argument and speaks the
// Chrome protocol on stdio: 4-byte little-endian length + UTF-8 JSON. The
// payload is echoed back, spooled to a temp file, and handed to the SwiftX
// binary next to this one via -NativeMessagingInput (which forwards to a
// running instance, or starts one).

import Foundation

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(
        Data("This executable receives data from the SwiftX browser addon; browsers launch it automatically.\n".utf8))
    exit(0)
}

func readExactly(_ count: Int) -> Data? {
    var data = Data()
    while data.count < count {
        guard let chunk = try? FileHandle.standardInput.read(upToCount: count - data.count),
              !chunk.isEmpty else { return nil }
        data.append(chunk)
    }
    return data
}

guard let lengthData = readExactly(4) else { exit(1) }
let length = lengthData.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
guard length > 0, length < 1024 * 1024, let payload = readExactly(Int(length)) else { exit(1) }

// echo back so the extension sees the message was received
FileHandle.standardOutput.write(lengthData)
FileHandle.standardOutput.write(payload)

let temp = FileManager.default.temporaryDirectory
    .appendingPathComponent("swiftx-nmh-\(UUID().uuidString).json")
try? payload.write(to: temp)

// "SwiftX" inside the app bundle; "swiftx" beside a bare swift-build binary
let siblings = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    .deletingLastPathComponent()
for name in ["SwiftX", "swiftx"] {
    let app = siblings.appendingPathComponent(name)
    guard FileManager.default.isExecutableFile(atPath: app.path) else { continue }
    let process = Process()
    process.executableURL = app
    process.arguments = ["-NativeMessagingInput", temp.path]
    // stdio stays clean: stray child output would corrupt the browser channel
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    break
}
