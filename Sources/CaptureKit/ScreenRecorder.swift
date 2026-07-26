// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Screen recording: SCStream frames feed either an AVAssetWriter (MP4,
// H.264/HEVC, optional AAC audio tracks) or a GIF encoder (ImageIO).
// Pause drops frames and shifts later timestamps back by the gap.
// No ffmpeg dependency (WebM and friends transcode after the fact).

import AVFoundation
import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import VideoToolbox

public enum RecordingFormat: Equatable {
    case movie(hevc: Bool)
    case gif

    public var fileExtension: String {
        switch self {
        case .movie: return "mp4"
        case .gif: return "gif"
        }
    }
}

public enum RecordingError: LocalizedError {
    case noDisplay
    case noWindow
    case noFrames
    case writerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display found for the recording area."
        case .noWindow: return "No recordable window found for the frontmost app."
        case .noFrames: return "The recording captured no frames."
        case .writerFailed(let reason): return "Could not write the recording: \(reason)"
        }
    }
}

/// Compresses raw BGRA sample buffers into an MP4 file, plus optional AAC
/// audio tracks (system audio and microphone land on separate tracks).
final class MovieWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneInput: AVAssetWriterInput?
    private var sessionStarted = false

    init(url: URL, width: Int, height: Int, hevc: Bool,
         systemAudio: Bool = false, microphone: Bool = false) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: hevc ? AVVideoCodecType.hevc : .h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)

        func makeAudioInput() -> AVAssetWriterInput {
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ])
            audioInput.expectsMediaDataInRealTime = true
            writer.add(audioInput)
            return audioInput
        }
        self.writer = writer
        self.input = input
        systemAudioInput = systemAudio ? makeAudioInput() : nil
        microphoneInput = microphone ? makeAudioInput() : nil

        guard writer.startWriting() else {
            throw RecordingError.writerFailed(writer.error?.localizedDescription ?? "startWriting failed")
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !sessionStarted {
            writer.startSession(atSourceTime: pts)
            sessionStarted = true
        }
        // ponytail: drop the frame when the encoder is behind; realtime capture can't wait
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    func appendSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        appendAudio(sampleBuffer, to: systemAudioInput)
    }

    func appendMicrophone(_ sampleBuffer: CMSampleBuffer) {
        appendAudio(sampleBuffer, to: microphoneInput)
    }

    /// Audio arriving before the first video frame is dropped: the writer
    /// session starts at the first video PTS, and video defines the timeline.
    private func appendAudio(_ sampleBuffer: CMSampleBuffer, to audioInput: AVAssetWriterInput?) {
        guard sessionStarted, let audioInput, audioInput.isReadyForMoreMediaData else { return }
        audioInput.append(sampleBuffer)
    }

    func finish() async throws {
        guard sessionStarted else {
            writer.cancelWriting()
            throw RecordingError.noFrames
        }
        input.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed {
            throw RecordingError.writerFailed(writer.error?.localizedDescription ?? "finishWriting failed")
        }
    }

    func cancel() {
        writer.cancelWriting()
    }
}

/// Accumulates frames and writes an animated GIF with per-frame delays
/// taken from the real capture timestamps.
/// ponytail: frames live in memory - fine for the short clips GIFs are for;
/// spill to disk if long GIF recordings ever matter.
final class GIFEncoder {
    private var frames: [(image: CGImage, pts: CMTime)] = []
    var frameCount: Int { frames.count }

    func append(_ image: CGImage, presentationTime: CMTime) {
        frames.append((image, presentationTime))
    }

    func write(to url: URL, defaultDelay: Double) throws {
        guard !frames.isEmpty else { throw RecordingError.noFrames }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil
        ) else { throw RecordingError.writerFailed("could not create GIF destination") }

        let loopForever = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(destination, loopForever as CFDictionary)

        for (index, frame) in frames.enumerated() {
            let delay = index + 1 < frames.count
                ? (frames[index + 1].pts - frame.pts).seconds
                : defaultDelay
            let properties = [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay
            ]]
            CGImageDestinationAddImage(destination, frame.image, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw RecordingError.writerFailed("could not finalize GIF")
        }
    }
}

/// Records a display, region or window to an MP4 or GIF file.
/// Create with `start(...)`, end with `stop()` (returns the file URL)
/// or `abort()` (deletes the partial file).
public final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    public enum Target {
        case display(NSScreen)
        /// Cocoa global coordinates (bottom-left origin); clamped to the dominant display.
        case region(CGRect)
        case frontmostWindow(pid_t)
    }

    public let outputURL: URL
    private let format: RecordingFormat
    private let defaultFrameDelay: Double
    private var stream: SCStream?
    private var movieWriter: MovieWriter?
    private var gifEncoder: GIFEncoder?
    // all writer access happens on this queue (SCStream sample handler + fences from stop/abort)
    private let sampleQueue = DispatchQueue(label: "com.retrohazard.swiftx.recorder")

    // Pause: frames are dropped while paused; on resume the wall-clock gap is
    // added to an offset that shifts every later PTS, so the output has no hole.
    // All three fields are touched only on sampleQueue.
    private var isPausedFlag = false
    private var pauseStartedAt: CMTime = .invalid
    private var pauseOffset: CMTime = .zero

    public var isPaused: Bool { sampleQueue.sync { isPausedFlag } }

    public func pause() {
        sampleQueue.sync {
            guard !isPausedFlag else { return }
            isPausedFlag = true
            // SCStream stamps buffers with the host clock, so measure gaps on it too
            pauseStartedAt = CMClockGetTime(CMClockGetHostTimeClock())
        }
    }

    public func resume() {
        sampleQueue.sync {
            guard isPausedFlag else { return }
            isPausedFlag = false
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            pauseOffset = CMTimeAdd(pauseOffset, CMTimeSubtract(now, pauseStartedAt))
        }
    }

    /// Returns a copy of the buffer with every timestamp shifted back by
    /// `offset`; returns the original when there is nothing to shift.
    static func retimed(_ sampleBuffer: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer {
        guard offset != .zero else { return sampleBuffer }
        var count = 0
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0,
                                               arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return sampleBuffer }
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count,
                                               arrayToFill: &timings, entriesNeededOut: &count)
        for index in timings.indices {
            timings[index].presentationTimeStamp =
                CMTimeSubtract(timings[index].presentationTimeStamp, offset)
            if timings[index].decodeTimeStamp.isValid {
                timings[index].decodeTimeStamp =
                    CMTimeSubtract(timings[index].decodeTimeStamp, offset)
            }
        }
        var adjusted: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: count, sampleTimingArray: &timings, sampleBufferOut: &adjusted
        )
        return adjusted ?? sampleBuffer
    }

    private init(outputURL: URL, format: RecordingFormat, fps: Int) {
        self.outputURL = outputURL
        self.format = format
        self.defaultFrameDelay = 1.0 / Double(max(1, fps))
    }

    /// `excludingWindowIDs` keeps our own recording HUD (border + control
    /// strip) out of display/region recordings; the HUD windows also set
    /// sharingType == .none as a second line of defense.
    public static func start(
        target: Target, format: RecordingFormat, fps: Int, outputURL: URL, showsCursor: Bool = true,
        systemAudio: Bool = false, microphone: Bool = false,
        excludingWindowIDs: [CGWindowID] = []
    ) async throws -> ScreenRecorder {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let excludedWindows = content.windows.filter { excludingWindowIDs.contains($0.windowID) }
        let configuration = SCStreamConfiguration()
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
        configuration.showsCursor = showsCursor
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 6

        // audio only makes sense for movie output; GIFs ignore it
        let wantsSystemAudio: Bool
        var wantsMicrophone = false
        if case .movie = format {
            wantsSystemAudio = systemAudio
            if systemAudio {
                configuration.capturesAudio = true
                configuration.sampleRate = 48000
                configuration.channelCount = 2
                configuration.excludesCurrentProcessAudio = true
            }
            if microphone {
                // SCStream microphone capture arrived in macOS 15
                if #available(macOS 15.0, *) {
                    configuration.captureMicrophone = true
                    configuration.microphoneCaptureDeviceID = nil // system default input
                    wantsMicrophone = true
                }
            }
        } else {
            wantsSystemAudio = false
        }

        let filter: SCContentFilter
        switch target {
        case .display(let screen):
            filter = SCContentFilter(display: try scDisplay(for: screen, in: content),
                                     excludingWindows: excludedWindows)
            let scale = screen.backingScaleFactor
            configuration.width = Int(screen.frame.width * scale)
            configuration.height = Int(screen.frame.height * scale)

        case .region(let cocoaRect):
            guard let screen = NSScreen.screens
                .filter({ $0.frame.intersects(cocoaRect) })
                .max(by: { $0.frame.intersection(cocoaRect).area < $1.frame.intersection(cocoaRect).area })
            else { throw RecordingError.noDisplay }
            let clamped = cocoaRect.intersection(screen.frame)
            filter = SCContentFilter(display: try scDisplay(for: screen, in: content),
                                     excludingWindows: excludedWindows)
            // sourceRect is in points, local to the display, top-left origin
            configuration.sourceRect = CGRect(
                x: clamped.minX - screen.frame.minX,
                y: screen.frame.maxY - clamped.maxY,
                width: clamped.width,
                height: clamped.height
            )
            let scale = screen.backingScaleFactor
            configuration.width = Int(clamped.width * scale)
            configuration.height = Int(clamped.height * scale)

        case .frontmostWindow(let pid):
            let window = content.windows
                .filter { $0.owningApplication?.processID == pid && $0.isOnScreen && $0.windowLayer == 0 }
                .max { $0.frame.area < $1.frame.area }
            guard let window else { throw RecordingError.noWindow }
            filter = SCContentFilter(desktopIndependentWindow: window)
            let scale = NSScreen.screens
                .first { ScreenCoordinates.cgFromCocoa($0.frame).intersects(window.frame) }?
                .backingScaleFactor ?? 2
            configuration.width = Int(window.frame.width * scale)
            configuration.height = Int(window.frame.height * scale)
        }

        // even pixel dimensions keep H.264 encoders happy
        configuration.width -= configuration.width % 2
        configuration.height -= configuration.height % 2

        let recorder = ScreenRecorder(outputURL: outputURL, format: format, fps: fps)
        switch format {
        case .movie(let hevc):
            recorder.movieWriter = try MovieWriter(
                url: outputURL, width: configuration.width, height: configuration.height, hevc: hevc,
                systemAudio: wantsSystemAudio, microphone: wantsMicrophone
            )
        case .gif:
            recorder.gifEncoder = GIFEncoder()
        }

        let stream = SCStream(filter: filter, configuration: configuration, delegate: recorder)
        try stream.addStreamOutput(recorder, type: .screen, sampleHandlerQueue: recorder.sampleQueue)
        if wantsSystemAudio {
            try stream.addStreamOutput(recorder, type: .audio, sampleHandlerQueue: recorder.sampleQueue)
        }
        if wantsMicrophone, #available(macOS 15.0, *) {
            try stream.addStreamOutput(recorder, type: .microphone, sampleHandlerQueue: recorder.sampleQueue)
        }
        try await stream.startCapture()
        recorder.stream = stream
        return recorder
    }

    /// Stops capturing, finalizes the file and returns its URL.
    public func stop() async throws -> URL {
        try? await stream?.stopCapture()
        stream = nil
        sampleQueue.sync {} // fence: let in-flight sample callbacks drain

        if let movieWriter {
            try await movieWriter.finish()
        } else if let gifEncoder {
            try gifEncoder.write(to: outputURL, defaultDelay: defaultFrameDelay)
        }
        return outputURL
    }

    /// Stops capturing and deletes whatever was written.
    public func abort() async {
        try? await stream?.stopCapture()
        stream = nil
        sampleQueue.sync {}
        movieWriter?.cancel()
        try? FileManager.default.removeItem(at: outputURL)
    }

    // MARK: - SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard buffer.isValid, !isPausedFlag else { return } // handler runs on sampleQueue
        let sampleBuffer = Self.retimed(buffer, by: pauseOffset)
        if type == .audio {
            movieWriter?.appendSystemAudio(sampleBuffer)
            return
        }
        if #available(macOS 15.0, *), type == .microphone {
            movieWriter?.appendMicrophone(sampleBuffer)
            return
        }
        guard type == .screen else { return }
        // SCStream also delivers idle/incomplete frames; only encode complete ones
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusValue) == .complete
        else { return }

        if let movieWriter {
            movieWriter.append(sampleBuffer)
        } else if let gifEncoder, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            var cgImage: CGImage?
            VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &cgImage)
            if let cgImage {
                gifEncoder.append(cgImage, presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            }
        }
    }

    // MARK: - Internals

    private static func scDisplay(for screen: NSScreen, in content: SCShareableContent) throws -> SCDisplay {
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard let display = content.displays.first(where: { $0.displayID == id }) else {
            throw RecordingError.noDisplay
        }
        return display
    }
}
