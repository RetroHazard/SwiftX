// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import CoreGraphics
import Testing
@testable import ToolsKit

struct ImageToolsTests {
    static func solid(_ color: (CGFloat, CGFloat, CGFloat), width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// RGBA of the pixel at top-left based (x, y).
    static func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var rgba = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8,
                                bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y),
                                       width: image.width, height: image.height))
        return (rgba[0], rgba[1], rgba[2], rgba[3])
    }

    @Test func combinesHorizontallyAndVerticallyWithSpacing() {
        let a = Self.solid((1, 0, 0), width: 10, height: 20)
        let b = Self.solid((0, 0, 1), width: 30, height: 40)

        let horizontal = ImageTools.combine([a, b], orientation: .horizontal, spacing: 5)!
        #expect(horizontal.width == 45 && horizontal.height == 40)

        let vertical = ImageTools.combine([a, b], orientation: .vertical, spacing: 5)!
        #expect(vertical.width == 30 && vertical.height == 65)
        // first image sits at the visual top-left
        #expect(Self.pixel(vertical, x: 5, y: 5).r == 255)
        // below the spacing gap, the second image is blue
        #expect(Self.pixel(vertical, x: 5, y: 30).b == 255)
    }

    @Test func centerAlignmentCentersTheNarrowImage() {
        let narrow = Self.solid((1, 0, 0), width: 10, height: 10)
        let wide = Self.solid((0, 0, 1), width: 30, height: 10)
        let combined = ImageTools.combine([narrow, wide], orientation: .vertical, alignment: .center)!
        #expect(Self.pixel(combined, x: 15, y: 5).r == 255)   // centered red
        #expect(Self.pixel(combined, x: 2, y: 5).a == 0)      // transparent margin
    }

    @Test func wrapAfterProducesAGrid() {
        let tiles = (0..<4).map { _ in Self.solid((0, 1, 0), width: 10, height: 10) }
        let grid = ImageTools.combine(tiles, orientation: .horizontal, wrapAfter: 2)!
        #expect(grid.width == 20 && grid.height == 20)
    }

    @Test func splitsIntoRowMajorTilesWithRemainderInLast() {
        let image = Self.solid((1, 1, 1), width: 100, height: 60)
        let tiles = ImageTools.split(image, rows: 2, columns: 3)
        #expect(tiles.count == 6)
        #expect(tiles[0].width == 33 && tiles[0].height == 30)
        #expect(tiles[2].width == 34)  // last column takes the remainder
        #expect(tiles[5].width == 34 && tiles[5].height == 30)
    }

    @Test func splitRejectsImpossibleGrids() {
        let image = Self.solid((1, 1, 1), width: 4, height: 4)
        #expect(ImageTools.split(image, rows: 0, columns: 2).isEmpty)
        #expect(ImageTools.split(image, rows: 8, columns: 1).isEmpty)
    }
}
