// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Video thumbnailer: N evenly spaced frames, optionally composed into a
// timestamped contact-sheet grid (C# VideoThumbnailOptions defaults: 9
// frames, 3 columns, 10 px spacing/padding, timestamps on).

import AppKit
import AVFoundation

public struct VideoThumbnailOptions: Sendable {
    public var count = 9
    public var columns = 3
    public var spacing = 10
    public var padding = 10
    public var maxThumbnailWidth = 512
    public var addTimestamp = true

    public init() {}
}

public enum VideoThumbnailer {
    public struct Frame: @unchecked Sendable {
        public let image: CGImage
        public let time: TimeInterval
    }

    /// Frames at (i + 0.5) / count through the video, so a 1-frame request
    /// lands mid-video rather than on the black opening frame.
    public static func frames(from url: URL, options: VideoThumbnailOptions = .init()) async throws -> [Frame] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: options.maxThumbnailWidth, height: 0)

        var result: [Frame] = []
        for index in 0..<max(1, options.count) {
            let seconds = duration * (Double(index) + 0.5) / Double(max(1, options.count))
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            let (image, actual) = try await generator.image(at: time)
            result.append(Frame(image: image, time: actual.seconds))
        }
        return result
    }

    /// Contact sheet: timestamped frames in a grid with spacing and padding.
    public static func contactSheet(_ frames: [Frame], options: VideoThumbnailOptions = .init()) -> CGImage? {
        guard !frames.isEmpty else { return nil }
        let stamped = frames.map { frame in
            options.addTimestamp ? stamp(frame.image, label: timestamp(frame.time)) : frame.image
        }
        guard let grid = ImageTools.combine(stamped, orientation: .horizontal,
                                            spacing: options.spacing,
                                            wrapAfter: options.columns) else { return nil }
        guard options.padding > 0 else { return grid }

        let width = grid.width + options.padding * 2
        let height = grid.height + options.padding * 2
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return grid }
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(grid, in: CGRect(x: options.padding, y: options.padding,
                                      width: grid.width, height: grid.height))
        return context.makeImage()
    }

    public static func timestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Label in the bottom-right corner over a translucent box.
    private static func stamp(_ image: CGImage, label: String) -> CGImage {
        let size = NSSize(width: image.width, height: image.height)
        let nsImage = NSImage(size: size)
        nsImage.lockFocus()
        NSImage(cgImage: image, size: size).draw(in: NSRect(origin: .zero, size: size))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: max(10, CGFloat(image.height) / 18), weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        let textSize = text.size()
        let box = NSRect(x: size.width - textSize.width - 10, y: 4,
                         width: textSize.width + 8, height: textSize.height + 2)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: box, xRadius: 3, yRadius: 3).fill()
        text.draw(at: NSPoint(x: box.minX + 4, y: box.minY + 1))
        nsImage.unlockFocus()
        return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) ?? image
    }
}
