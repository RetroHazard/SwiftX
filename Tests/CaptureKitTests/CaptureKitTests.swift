// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CaptureKit

struct ScreenCoordinatesTests {
    @Test func cocoaToCG() {
        // 1080p primary display: a 100x50 rect whose Cocoa origin is (10, 20)
        // sits 20pt above the bottom, so its CG top is at 1080 - (20+50) = 1010
        let cocoa = CGRect(x: 10, y: 20, width: 100, height: 50)
        let cg = ScreenCoordinates.cgFromCocoa(cocoa, primaryHeight: 1080)
        #expect(cg == CGRect(x: 10, y: 1010, width: 100, height: 50))
    }

    @Test func displayLocalPixelRectOnPrimaryRetina() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let selection = CGRect(x: 100, y: 917, width: 200, height: 100)
        let pixels = ScreenCoordinates.displayLocalPixelRect(of: selection, in: screen, scale: 2)
        // top of selection is 1117 - (917+100) = 100pt from screen top -> 200px
        #expect(pixels == CGRect(x: 200, y: 200, width: 400, height: 200))
    }

    @Test func displayLocalPixelRectOnSecondaryDisplay() {
        // secondary display to the right of a 1728pt-wide primary
        let screen = CGRect(x: 1728, y: 0, width: 1920, height: 1080)
        let selection = CGRect(x: 1828, y: 0, width: 100, height: 1080)
        let pixels = ScreenCoordinates.displayLocalPixelRect(of: selection, in: screen, scale: 1)
        #expect(pixels == CGRect(x: 100, y: 0, width: 100, height: 1080))
    }
}

struct ImageWriterTests {
    private func makeImage(width: Int = 4, height: Int = 4) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test func pngRoundTrip() throws {
        let data = try #require(ImageWriter.pngData(makeImage()))
        #expect(!data.isEmpty)
        // PNG magic bytes
        #expect(data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))

        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 4)
        #expect(decoded.height == 4)
    }

    @Test func writeCreatesIntermediateDirectories() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareXTests-\(UUID().uuidString)/nested/deep")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("test.png")
        try ImageWriter.writePNG(makeImage(), to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
