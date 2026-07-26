// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import CoreGraphics
import Foundation
import Testing
@testable import CaptureKit

struct ScrollingCaptureStitcherTests {
    static let width = 200

    /// A frame whose row y shows the "document" row firstRow + y; every
    /// document row has a unique color so overlaps are unambiguous.
    static func frame(firstRow: Int, height: Int) -> ScrollingCaptureStitcher.Frame {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let document = firstRow + y
            for x in 0..<width {
                let i = (y * width + x) * 4
                data[i] = UInt8(document % 256)
                data[i + 1] = UInt8((document / 256) % 256)
                data[i + 2] = 77
                data[i + 3] = 255
            }
        }
        return ScrollingCaptureStitcher.Frame(width: width, height: height, data: data)
    }

    @Test func overlappingFramesStitchToFullDocument() {
        var stitcher = ScrollingCaptureStitcher(autoIgnoreBottomEdge: false)
        // 600-row viewport scrolled by 200 rows per frame: document 0..<1000
        for firstRow in [0, 200, 400] {
            let appended = stitcher.append(Self.frame(firstRow: firstRow, height: 600))
            #expect(appended, "frame at \(firstRow)")
        }
        #expect(stitcher.status == .successful)

        let image = stitcher.makeImage()
        #expect(image?.height == 1000)
        #expect(image?.width == Self.width)

        // stitched pixels must reproduce the document gradient exactly
        if let image, let stitched = ScrollingCaptureStitcher.Frame(image) {
            for row in [0, 250, 500, 750, 999] {
                let i = row * Self.width * 4
                #expect(stitched.data[i] == UInt8(row % 256), "row \(row)")
                #expect(stitched.data[i + 1] == UInt8((row / 256) % 256), "row \(row)")
            }
        }
    }

    @Test func nonOverlappingFrameFailsAndKeepsResult() {
        var stitcher = ScrollingCaptureStitcher(autoIgnoreBottomEdge: false)
        let first = stitcher.append(Self.frame(firstRow: 0, height: 600))
        #expect(first)
        // no shared rows with the first frame and no best guess yet
        let second = stitcher.append(Self.frame(firstRow: 5000, height: 600))
        #expect(!second)
        #expect(stitcher.status == .failed)
        #expect(stitcher.makeImage()?.height == 600)
    }

    @Test func identicalFramesCompareEqual() {
        #expect(Self.frame(firstRow: 40, height: 100) == Self.frame(firstRow: 40, height: 100))
        #expect(Self.frame(firstRow: 40, height: 100) != Self.frame(firstRow: 41, height: 100))
    }
}
