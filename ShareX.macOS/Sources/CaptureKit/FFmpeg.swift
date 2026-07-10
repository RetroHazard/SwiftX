// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Optional ffmpeg integration for formats VideoToolbox can't encode
// (WebM VP9/VP8, animated WebP, APNG). ffmpeg is never bundled - we use an
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

    /// Formats that only exist through a post-stop ffmpeg transcode.
    /// Raw values match the ScreenRecordCodec setting (uppercased).
    public enum TranscodeFormat: String, CaseIterable {
        case vp9 = "VP9"
        case vp8 = "VP8"
        case webp = "WEBP"
        case apng = "APNG"

        public var fileExtension: String {
            switch self {
            case .vp9, .vp8: return "webm"
            case .webp: return "webp"
            case .apng: return "apng" // matches C# FFmpegVideoCodec extension
            }
        }

        public var displayName: String {
            switch self {
            case .vp9: return "WebM (VP9)"
            case .vp8: return "WebM (VP8)"
            case .webp: return "WebP"
            case .apng: return "APNG"
            }
        }

        /// Output-side arguments (between `-i input` and the output path).
        var arguments: [String] {
            switch self {
            // crf + b:v 0 is libvpx constant-quality mode; row-mt uses all cores;
            // Opus carries any recorded audio through into the WebM
            case .vp9: return ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "32", "-row-mt", "1", "-c:a", "libopus"]
            case .vp8: return ["-c:v", "libvpx", "-b:v", "0", "-crf", "12", "-c:a", "libopus"]
            case .webp: return ["-c:v", "libwebp", "-loop", "0", "-q:v", "75", "-an"]
            case .apng: return ["-f", "apng", "-plays", "0", "-an"]
            }
        }
    }

    /// The full argument list a transcode runs with. Non-empty custom args
    /// replace the format preset (C# UseCustomCommands behavior).
    /// ponytail: custom args split on spaces - no shell quoting support;
    /// add real tokenization if someone needs paths-with-spaces in filters.
    static func transcodeArguments(
        input: String, output: String, format: TranscodeFormat, customArgs: String = ""
    ) -> [String] {
        var arguments = ["-y", "-i", input]
        let custom = customArgs.split(separator: " ").map(String.init)
        arguments += custom.isEmpty ? format.arguments : custom
        arguments.append(output)
        return arguments
    }

    /// Re-encodes a finished MP4 recording. Runs after the recording stops -
    /// transcoding preserves frame timing exactly, unlike piping realtime
    /// frames into ffmpeg.
    public static func transcode(
        input: URL, output: URL, format: TranscodeFormat, customArgs: String = ""
    ) async throws {
        guard let path = installedPath else {
            throw RecordingError.writerFailed("ffmpeg is not installed")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = transcodeArguments(
            input: input.path, output: output.path, format: format, customArgs: customArgs
        )
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
