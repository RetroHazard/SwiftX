// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Port of C# ScrollingCaptureManager.CombineImages: finds where the new frame
// overlaps the bottom of the stitched result by comparing pixel rows (memcmp),
// then appends only the new rows. Side margins are ignored (scrollbars), and
// a fixed bottom edge (sticky footers) can be detected and trimmed.

import CoreGraphics
import Foundation

public struct ScrollingCaptureStitcher {
    public enum Status { case successful, partiallySuccessful, failed }

    /// A frame as a tight RGBA8 buffer; row comparisons are memcmp on this.
    public struct Frame: Equatable, Sendable {
        let width: Int
        let height: Int
        let data: [UInt8]

        public init?(_ image: CGImage) {
            let width = image.width
            let height = image.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(
                    data: raw.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard ok else { return nil }
            self.width = width
            self.height = height
            self.data = buffer
        }

        init(width: Int, height: Int, data: [UInt8]) {
            self.width = width
            self.height = height
            self.data = data
        }

        func row(_ y: Int) -> Int { y * width * 4 }
    }

    public private(set) var status: Status = .failed
    private var result: Frame?
    private var bestMatchCount = 0
    private var bestMatchIndex = 0
    private var bestIgnoreBottomOffset = 0
    private let autoIgnoreBottomEdge: Bool

    public init(autoIgnoreBottomEdge: Bool) {
        self.autoIgnoreBottomEdge = autoIgnoreBottomEdge
    }

    /// Appends a frame to the stitched result. Returns false when no overlap
    /// was found (capture should stop); the result so far is kept.
    public mutating func append(_ current: Frame) -> Bool {
        guard let res = result else {
            result = current
            status = .successful
            return true
        }
        guard res.width == current.width else {
            status = .failed
            return false
        }

        let width = current.width
        let height = current.height
        let matchLimit = height / 2
        let sideOffset = min(max(50, width / 20), width / 3)
        let byteOffset = sideOffset * 4
        let compareLength = (width - sideOffset * 2) * 4

        func rowsEqual(_ resultY: Int, _ currentY: Int) -> Bool {
            res.data.withUnsafeBytes { a in
                current.data.withUnsafeBytes { b in
                    memcmp(a.baseAddress! + res.row(resultY) + byteOffset,
                           b.baseAddress! + current.row(currentY) + byteOffset,
                           compareLength) == 0
                }
            }
        }

        // Fixed UI at the frame bottom (sticky footer, horizontal scrollbar)
        // would break the overlap search; find how deep the identical bottom
        // region runs and skip past it.
        let ignoreBottomOffsetMax = height / 3
        var ignoreBottomOffset = max(50, height / 10)
        if autoIgnoreBottomEdge {
            for i in 0...ignoreBottomOffsetMax {
                let resultY = res.height - 1 - i
                let currentY = height - 1 - i
                if resultY < 0 || currentY < 0 { break }
                if !rowsEqual(resultY, currentY) {
                    ignoreBottomOffset += i
                    break
                }
            }
            ignoreBottomOffset = max(ignoreBottomOffset, bestIgnoreBottomOffset)
        }
        ignoreBottomOffset = min(ignoreBottomOffset, ignoreBottomOffsetMax)

        // For every candidate row in the new frame, count how many consecutive
        // rows (walking upward) match the result's bottom; keep the longest run.
        let resultBottom = res.height - ignoreBottomOffset - 1
        var matchCount = 0
        var matchIndex = 0
        var currentY = height - 1
        while currentY >= 0, matchCount < matchLimit {
            var run = 0
            var y = 0
            while currentY - y >= 0, run < matchLimit {
                let resultY = resultBottom - y
                guard resultY >= 0, rowsEqual(resultY, currentY - y) else { break }
                run += 1
                y += 1
            }
            if run > matchCount {
                matchCount = run
                matchIndex = currentY
            }
            currentY -= 1
        }

        // No overlap this frame: reuse the best offsets seen so far rather
        // than giving up (C# "best guess" - marks the result partial).
        var bestGuess = false
        if matchCount == 0, bestMatchCount > 0 {
            matchCount = bestMatchCount
            matchIndex = bestMatchIndex
            ignoreBottomOffset = bestIgnoreBottomOffset
            bestGuess = true
        }

        if matchCount > 0 {
            let matchHeight = height - matchIndex - 1
            if matchHeight > 0 {
                if matchCount > bestMatchCount {
                    bestMatchCount = matchCount
                    bestMatchIndex = matchIndex
                    bestIgnoreBottomOffset = ignoreBottomOffset
                }
                let keptHeight = res.height - ignoreBottomOffset
                var data = [UInt8](repeating: 0, count: (keptHeight + matchHeight) * width * 4)
                res.data.withUnsafeBytes { src in
                    data.replaceSubrange(0..<keptHeight * width * 4,
                                         with: src.prefix(keptHeight * width * 4))
                }
                current.data.withUnsafeBytes { src in
                    let start = current.row(matchIndex + 1)
                    data.replaceSubrange((keptHeight * width * 4)..<data.count,
                                         with: src[start..<(start + matchHeight * width * 4)])
                }
                result = Frame(width: width, height: keptHeight + matchHeight, data: data)
                if bestGuess {
                    status = .partiallySuccessful
                } else if status != .partiallySuccessful {
                    status = .successful
                }
                return true
            }
        }

        status = .failed
        return false
    }

    public func makeImage() -> CGImage? {
        guard let res = result,
              let provider = CGDataProvider(data: Data(res.data) as CFData) else { return nil }
        return CGImage(width: res.width, height: res.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: res.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
