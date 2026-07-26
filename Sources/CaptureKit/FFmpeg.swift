// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
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

        /// Only the libvpx codecs implement -pass; WebP/APNG are single-pass.
        public var supportsTwoPass: Bool {
            self == .vp9 || self == .vp8
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

    /// Analysis pass + encode pass sharing a stats file (C#
    /// ScreenRecordTwoPassEncoding). Pass 1 discards output (-f null) and
    /// audio; pass 2 writes the real file.
    static func twoPassArguments(
        input: String, output: String, format: TranscodeFormat, passLogFile: String
    ) -> [[String]] {
        let base = ["-y", "-i", input] + format.arguments
        return [
            base + ["-pass", "1", "-passlogfile", passLogFile, "-an", "-f", "null", "/dev/null"],
            base + ["-pass", "2", "-passlogfile", passLogFile, output]
        ]
    }

    /// Re-encodes a finished MP4 recording. Runs after the recording stops -
    /// transcoding preserves frame timing exactly, unlike piping realtime
    /// frames into ffmpeg.
    /// `twoPass` applies to VP9/VP8 preset encodes only; custom args and the
    /// single-pass-only formats fall back to one pass.
    public static func transcode(
        input: URL, output: URL, format: TranscodeFormat, customArgs: String = "",
        twoPass: Bool = false
    ) async throws {
        if twoPass, format.supportsTwoPass, customArgs.isEmpty {
            let logBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftx-ffmpeg2pass-\(UUID().uuidString)")
            defer { removeTemporaryFiles(prefix: logBase.lastPathComponent) }
            for passArguments in twoPassArguments(
                input: input.path, output: output.path, format: format, passLogFile: logBase.path
            ) {
                try await run(arguments: passArguments)
            }
            return
        }
        try await run(arguments: transcodeArguments(
            input: input.path, output: output.path, format: format, customArgs: customArgs
        ))
    }

    /// ffmpeg derives its stats file names from -passlogfile ("<base>-0.log",
    /// ...); sweep everything with the prefix.
    private static func removeTemporaryFiles(prefix: String) {
        let temporary = FileManager.default.temporaryDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: temporary.path) else { return }
        for item in items where item.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: temporary.appendingPathComponent(item))
        }
    }

    /// Codecs the Video Converter tool offers. Mirrors C# ConverterVideoCodecs,
    /// with VideoToolbox standing in for the nvenc/amf/qsv hardware encoders.
    public enum ConvertCodec: String, CaseIterable, Sendable {
        case x264 = "H.264 (x264)"
        case x265 = "H.265 / HEVC (x265)"
        case h264VideoToolbox = "H.264 (VideoToolbox hardware)"
        case hevcVideoToolbox = "HEVC (VideoToolbox hardware)"
        case vp9 = "WebM (VP9)"
        case vp8 = "WebM (VP8)"
        case gif = "GIF"
        case webp = "WebP animation"
        case apng = "APNG"

        public var fileExtension: String {
            switch self {
            case .x264, .x265, .h264VideoToolbox, .hevcVideoToolbox: return "mp4"
            case .vp9, .vp8: return "webm"
            case .gif: return "gif"
            case .webp: return "webp"
            case .apng: return "apng"
            }
        }

        /// CRF-style quality codecs show a quality slider; VideoToolbox is
        /// bitrate-driven; the animation formats have fixed presets.
        public var usesCRF: Bool {
            switch self {
            case .x264, .x265, .vp9, .vp8: return true
            default: return false
            }
        }

        public var usesBitrate: Bool {
            self == .h264VideoToolbox || self == .hevcVideoToolbox
        }

        public var defaultCRF: Int {
            switch self {
            case .x264: return 23
            case .x265: return 28
            case .vp9: return 32
            case .vp8: return 12
            default: return 0
            }
        }

        func arguments(crf: Int, bitrateKbps: Int) -> [String] {
            switch self {
            case .x264:
                return ["-c:v", "libx264", "-preset", "medium", "-crf", "\(crf)", "-c:a", "aac"]
            case .x265:
                // hvc1 tag so QuickTime/Photos accept the file
                return ["-c:v", "libx265", "-preset", "medium", "-crf", "\(crf)",
                        "-tag:v", "hvc1", "-c:a", "aac"]
            case .h264VideoToolbox:
                return ["-c:v", "h264_videotoolbox", "-b:v", "\(bitrateKbps)k", "-c:a", "aac"]
            case .hevcVideoToolbox:
                return ["-c:v", "hevc_videotoolbox", "-b:v", "\(bitrateKbps)k",
                        "-tag:v", "hvc1", "-c:a", "aac"]
            case .vp9:
                return ["-c:v", "libvpx-vp9", "-b:v", "0", "-crf", "\(crf)", "-row-mt", "1", "-c:a", "libopus"]
            case .vp8:
                return ["-c:v", "libvpx", "-b:v", "0", "-crf", "\(crf)", "-c:a", "libopus"]
            case .gif:
                // palettegen/paletteuse in one pass: proper 256-color palette
                return ["-vf", "fps=15,scale=iw:ih:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse",
                        "-loop", "0"]
            case .webp:
                return ["-c:v", "libwebp", "-loop", "0", "-q:v", "75", "-an"]
            case .apng:
                return ["-f", "apng", "-plays", "0", "-an"]
            }
        }
    }

    /// Non-empty custom args replace the codec preset, like the recorder.
    static func convertArguments(
        input: String, output: String, codec: ConvertCodec,
        crf: Int, bitrateKbps: Int, customArgs: String = ""
    ) -> [String] {
        var arguments = ["-y", "-i", input]
        let custom = customArgs.split(separator: " ").map(String.init)
        arguments += custom.isEmpty ? codec.arguments(crf: crf, bitrateKbps: bitrateKbps) : custom
        arguments.append(output)
        return arguments
    }

    public static func convert(
        input: URL, output: URL, codec: ConvertCodec,
        crf: Int, bitrateKbps: Int, customArgs: String = ""
    ) async throws {
        try await run(arguments: convertArguments(
            input: input.path, output: output.path, codec: codec,
            crf: crf, bitrateKbps: bitrateKbps, customArgs: customArgs
        ))
    }

    private static func run(arguments: [String]) async throws {
        guard let path = installedPath else {
            throw RecordingError.writerFailed("ffmpeg is not installed")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
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
