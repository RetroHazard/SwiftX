// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt
//
// Tests the two recording sinks directly; the SCStream glue needs a live
// screen-recording permission and is exercised manually.

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CaptureKit

private func tempURL(_ ext: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("sharex-recorder-\(UUID().uuidString)")
        .appendingPathExtension(ext)
}

private func makeImage(width: Int, height: Int, gray: CGFloat) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func makeSampleBuffer(width: Int, height: Int, pts: CMTime) throws -> CMSampleBuffer {
    var pixelBuffer: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
    let buffer = try #require(pixelBuffer)

    var formatDescription: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &formatDescription
    )
    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: pts, decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: buffer,
        formatDescription: try #require(formatDescription),
        sampleTiming: &timing, sampleBufferOut: &sampleBuffer
    )
    return try #require(sampleBuffer)
}

struct MovieWriterTests {
    @Test func writesPlayableMP4() async throws {
        let url = tempURL("mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try MovieWriter(url: url, width: 64, height: 64, hevc: false)
        for frame in 0..<10 {
            writer.append(try makeSampleBuffer(width: 64, height: 64,
                                               pts: CMTime(value: CMTimeValue(frame), timescale: 30)))
            // give the realtime encoder a beat so frames aren't dropped as "not ready"
            try await Task.sleep(for: .milliseconds(10))
        }
        try await writer.finish()

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        #expect(duration.seconds > 0.2)
        #expect(tracks.count == 1)
    }

    @Test func audioEnabledWriterStillFinishesWithVideoOnly() async throws {
        // audio tracks are declared up front but AAC inputs with no samples
        // must not block finalization (mic may simply be silent/denied)
        let url = tempURL("mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try MovieWriter(url: url, width: 64, height: 64, hevc: false,
                                     systemAudio: true, microphone: true)
        for frame in 0..<5 {
            writer.append(try makeSampleBuffer(width: 64, height: 64,
                                               pts: CMTime(value: CMTimeValue(frame), timescale: 30)))
            try await Task.sleep(for: .milliseconds(10))
        }
        try await writer.finish()

        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        #expect(videoTracks.count == 1)
    }

    @Test func finishWithoutFramesThrows() async throws {
        let url = tempURL("mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        let writer = try MovieWriter(url: url, width: 64, height: 64, hevc: false)
        await #expect(throws: RecordingError.self) {
            try await writer.finish()
        }
    }
}

struct PauseRetimingTests {
    @Test func retimedShiftsPresentationTimestampBack() throws {
        let buffer = try makeSampleBuffer(width: 8, height: 8,
                                          pts: CMTime(seconds: 10, preferredTimescale: 600))
        let offset = CMTime(seconds: 4, preferredTimescale: 600)
        let shifted = ScreenRecorder.retimed(buffer, by: offset)
        let pts = CMSampleBufferGetPresentationTimeStamp(shifted)
        #expect(abs(pts.seconds - 6) < 0.001)
    }

    @Test func zeroOffsetReturnsOriginalBuffer() throws {
        let buffer = try makeSampleBuffer(width: 8, height: 8,
                                          pts: CMTime(seconds: 3, preferredTimescale: 600))
        #expect(ScreenRecorder.retimed(buffer, by: .zero) === buffer)
    }
}

struct GIFEncoderTests {
    @Test func writesAnimatedGIFWithRealFrameDelays() throws {
        let url = tempURL("gif")
        defer { try? FileManager.default.removeItem(at: url) }

        let encoder = GIFEncoder()
        encoder.append(makeImage(width: 32, height: 32, gray: 0.2), presentationTime: CMTime(seconds: 0.0, preferredTimescale: 600))
        encoder.append(makeImage(width: 32, height: 32, gray: 0.5), presentationTime: CMTime(seconds: 0.1, preferredTimescale: 600))
        encoder.append(makeImage(width: 32, height: 32, gray: 0.8), presentationTime: CMTime(seconds: 0.3, preferredTimescale: 600))
        try encoder.write(to: url, defaultDelay: 1.0 / 15.0)

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == "com.compuserve.gif")
        #expect(CGImageSourceGetCount(source) == 3)

        func delay(ofFrame index: Int) -> Double {
            let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            return gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? -1
        }
        // frame delay = gap to the next frame; last frame uses the default
        #expect(abs(delay(ofFrame: 0) - 0.1) < 0.01)
        #expect(abs(delay(ofFrame: 1) - 0.2) < 0.01)
        #expect(abs(delay(ofFrame: 2) - 1.0 / 15.0) < 0.01)
    }

    @Test func emptyEncoderThrows() {
        let url = tempURL("gif")
        #expect(throws: RecordingError.self) {
            try GIFEncoder().write(to: url, defaultDelay: 0.1)
        }
    }
}
