// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt

import AVFoundation
import CoreMedia
import Foundation
import Testing
@testable import CaptureKit
@testable import ToolsKit

struct VideoThumbnailerTests {
    @Test func contactSheetLaysOutGridWithSpacingAndPadding() {
        var options = VideoThumbnailOptions()
        options.columns = 3
        options.spacing = 10
        options.padding = 10
        options.addTimestamp = false
        let frames = (0..<4).map {
            VideoThumbnailer.Frame(image: ImageToolsTests.solid((0, 1, 0), width: 100, height: 60),
                                   time: Double($0))
        }
        let sheet = VideoThumbnailer.contactSheet(frames, options: options)!
        // row 1: three tiles + two gaps; row 2: one tile; plus padding all around
        #expect(sheet.width == 100 * 3 + 10 * 2 + 20)
        #expect(sheet.height == 60 * 2 + 10 + 20)
    }

    @Test func timestampsFormatLikeVideoPlayers() {
        #expect(VideoThumbnailer.timestamp(65) == "1:05")
        #expect(VideoThumbnailer.timestamp(3725) == "1:02:05")
        #expect(VideoThumbnailer.timestamp(0) == "0:00")
    }

    @Test func extractsRequestedFrameCountFromARealVideo() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sharex-vthumb-test-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await Self.writeTestMovie(to: url, frames: 30)

        var options = VideoThumbnailOptions()
        options.count = 4
        options.maxThumbnailWidth = 32
        let frames = try await VideoThumbnailer.frames(from: url, options: options)
        #expect(frames.count == 4)
        #expect(frames.allSatisfy { $0.image.width <= 32 })
        // times ascend through the video
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.time <= $1.time })
    }

    static func writeTestMovie(to url: URL, frames: Int) async throws {
        let writer = try MovieWriter(url: url, width: 64, height: 64, hevc: false)
        for frame in 0..<frames {
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
            try await Task.sleep(for: .milliseconds(5))
        }
        try await writer.finish()
    }
}
