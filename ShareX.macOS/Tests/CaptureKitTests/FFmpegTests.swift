// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import AVFoundation
import Foundation
import Testing
@testable import CaptureKit

struct FFmpegLocatorTests {
    @Test func findsFirstExecutableCandidate() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sharex-ffmpeg-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let fake = dir.appendingPathComponent("ffmpeg")
        try "#!/bin/zsh\n".write(to: fake, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)

        let missing = dir.appendingPathComponent("nope/ffmpeg").path
        #expect(FFmpeg.locate(searchPaths: [missing, fake.path]) == fake.path)
        #expect(FFmpeg.locate(searchPaths: [missing]) == nil)
    }

    @Test func nonExecutableFileIsNotFound() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sharex-ffmpeg-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let plain = dir.appendingPathComponent("ffmpeg")
        try "not a binary".write(to: plain, atomically: true, encoding: .utf8)
        #expect(FFmpeg.locate(searchPaths: [plain.path]) == nil)
    }
}

struct FFmpegTranscodeTests {
    // runs only on machines that actually have ffmpeg installed
    @Test(.enabled(if: FFmpeg.installedPath != nil))
    func transcodesMP4ToWebM() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("sharex-webm-test-\(UUID().uuidString)")
        let mp4 = base.appendingPathExtension("mp4")
        let webm = base.appendingPathExtension("webm")
        defer {
            try? FileManager.default.removeItem(at: mp4)
            try? FileManager.default.removeItem(at: webm)
        }

        let writer = try MovieWriter(url: mp4, width: 64, height: 64, hevc: false)
        for frame in 0..<10 {
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
            let buffer = try #require(pixelBuffer)
            var formatDescription: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &formatDescription
            )
            var timing = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: 30),
                presentationTimeStamp: CMTime(value: CMTimeValue(frame), timescale: 30),
                decodeTimeStamp: .invalid
            )
            var sampleBuffer: CMSampleBuffer?
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: buffer,
                formatDescription: try #require(formatDescription),
                sampleTiming: &timing, sampleBufferOut: &sampleBuffer
            )
            writer.append(try #require(sampleBuffer))
            try await Task.sleep(for: .milliseconds(10))
        }
        try await writer.finish()

        try await FFmpeg.transcode(input: mp4, output: webm, format: .vp9)
        let size = try FileManager.default.attributesOfItem(atPath: webm.path)[.size] as? Int ?? 0
        #expect(size > 0)
    }
}

struct FFmpegArgumentTests {
    @Test func presetArgumentsWrapInputAndOutput() {
        let args = FFmpeg.transcodeArguments(input: "in.mp4", output: "out.webm", format: .vp9)
        #expect(args.first == "-y")
        #expect(Array(args[1...2]) == ["-i", "in.mp4"])
        #expect(args.last == "out.webm")
        #expect(args.contains("libvpx-vp9"))
    }

    @Test func customArgumentsReplaceThePreset() {
        let args = FFmpeg.transcodeArguments(
            input: "in.mp4", output: "out.webm", format: .vp9,
            customArgs: "-c:v libvpx-vp9 -crf 24"
        )
        #expect(args == ["-y", "-i", "in.mp4", "-c:v", "libvpx-vp9", "-crf", "24", "out.webm"])
        #expect(!args.contains("-row-mt")) // preset gone
    }

    @Test func converterPresetsBuildValidArgumentLists() {
        let args = FFmpeg.convertArguments(input: "in.mov", output: "out.mp4",
                                           codec: .x264, crf: 20, bitrateKbps: 3000)
        #expect(args == ["-y", "-i", "in.mov", "-c:v", "libx264", "-preset", "medium",
                         "-crf", "20", "-c:a", "aac", "out.mp4"])

        let hardware = FFmpeg.convertArguments(input: "in.mov", output: "out.mp4",
                                               codec: .hevcVideoToolbox, crf: 0, bitrateKbps: 4500)
        #expect(hardware.contains("hevc_videotoolbox"))
        #expect(hardware.contains("4500k"))

        let custom = FFmpeg.convertArguments(input: "a", output: "b", codec: .x264,
                                             crf: 23, bitrateKbps: 0, customArgs: "-c:v libaom-av1")
        #expect(custom == ["-y", "-i", "a", "-c:v", "libaom-av1", "b"])
    }

    @Test func converterCodecsKnowTheirContainersAndQualityMode() {
        #expect(FFmpeg.ConvertCodec.x265.fileExtension == "mp4")
        #expect(FFmpeg.ConvertCodec.vp9.fileExtension == "webm")
        #expect(FFmpeg.ConvertCodec.gif.fileExtension == "gif")
        #expect(FFmpeg.ConvertCodec.x264.usesCRF && !FFmpeg.ConvertCodec.x264.usesBitrate)
        #expect(FFmpeg.ConvertCodec.h264VideoToolbox.usesBitrate && !FFmpeg.ConvertCodec.h264VideoToolbox.usesCRF)
        #expect(!FFmpeg.ConvertCodec.gif.usesCRF && !FFmpeg.ConvertCodec.gif.usesBitrate)
    }

    @Test func formatExtensionsMatchTheirContainers() {
        #expect(FFmpeg.TranscodeFormat.vp9.fileExtension == "webm")
        #expect(FFmpeg.TranscodeFormat.vp8.fileExtension == "webm")
        #expect(FFmpeg.TranscodeFormat.webp.fileExtension == "webp")
        #expect(FFmpeg.TranscodeFormat.apng.fileExtension == "apng")
        // codec setting strings resolve to transcode targets (via uppercased())
        #expect(FFmpeg.TranscodeFormat(rawValue: "VP8") == .vp8)
        #expect(FFmpeg.TranscodeFormat(rawValue: "H264") == nil)
    }
}
