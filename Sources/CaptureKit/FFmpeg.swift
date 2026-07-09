// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Optional ffmpeg integration for formats VideoToolbox can't encode
// (WebM/VP9 today; WebP/APNG later). ffmpeg is never bundled - we use an
// existing install, which the Settings window can kick off via Homebrew.

import Foundation

public enum FFmpeg {
    /// Homebrew (Apple Silicon + Intel) and MacPorts locations. PATH lookup is
    /// useless here: Finder-launched apps get a minimal PATH.
    public static let defaultSearchPaths = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/opt/local/bin/ffmpeg"
    ]

    public static var installedPath: String? {
        locate(searchPaths: defaultSearchPaths)
    }

    public static func locate(searchPaths: [String]) -> String? {
        searchPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static var homebrewPath: String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Re-encodes a finished MP4 recording as WebM/VP9. Runs after the
    /// recording stops - transcoding preserves frame timing exactly, unlike
    /// piping realtime frames into ffmpeg.
    public static func transcodeToWebM(input: URL, output: URL) async throws {
        guard let path = installedPath else {
            throw RecordingError.writerFailed("ffmpeg is not installed")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        // crf 32 + b:v 0 is the libvpx-vp9 constant-quality mode; row-mt uses all cores
        process.arguments = [
            "-y", "-i", input.path,
            "-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "32", "-row-mt", "1",
            "-an", output.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
        }
        guard process.terminationStatus == 0 else {
            throw RecordingError.writerFailed("ffmpeg exited with status \(process.terminationStatus)")
        }
    }
}
