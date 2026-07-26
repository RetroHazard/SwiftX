// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

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

    @Test(arguments: ImageFileFormat.allCases)
    func everyFormatEncodesAndDecodes(format: ImageFileFormat) throws {
        let data = try #require(ImageWriter.data(makeImage(), format: format))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.width == 4)
        #expect(decoded.height == 4)
    }

    @Test func jpegQualityChangesOutputSize() throws {
        let image = makeImage(width: 256, height: 256)
        let low = try #require(ImageWriter.data(image, format: .jpeg, jpegQuality: 10))
        let high = try #require(ImageWriter.data(image, format: .jpeg, jpegQuality: 100))
        #expect(low.count < high.count)
    }

    @Test func effectiveFormatHonorsAutoJPEG() {
        #expect(ImageWriter.effectiveFormat(named: "PNG", autoUseJPEG: true, autoUseJPEGSize: 2048,
                                            width: 3000, height: 100) == .jpeg)
        #expect(ImageWriter.effectiveFormat(named: "PNG", autoUseJPEG: false, autoUseJPEGSize: 2048,
                                            width: 3000, height: 100) == .png)
        #expect(ImageWriter.effectiveFormat(named: "PNG", autoUseJPEG: true, autoUseJPEGSize: 2048,
                                            width: 2048, height: 2048) == .png)
        // unknown names (future C# values) fall back to PNG
        #expect(ImageWriter.effectiveFormat(named: "WEBP", autoUseJPEG: false, autoUseJPEGSize: 2048,
                                            width: 10, height: 10) == .png)
    }

    @Test func effectiveJPEGQualityUsesAutoQualityOnlyWhenForced() {
        // PNG forced to JPEG by the size rule -> the auto quality applies
        #expect(ImageWriter.effectiveJPEGQuality(configuredFormatName: "PNG", effectiveFormat: .jpeg,
                                                 jpegQuality: 90, autoJPEGQuality: 60) == 60)
        // JPEG chosen explicitly -> the regular quality applies
        #expect(ImageWriter.effectiveJPEGQuality(configuredFormatName: "JPEG", effectiveFormat: .jpeg,
                                                 jpegQuality: 90, autoJPEGQuality: 60) == 90)
        // not JPEG at all -> quality is irrelevant but stays the regular one
        #expect(ImageWriter.effectiveJPEGQuality(configuredFormatName: "PNG", effectiveFormat: .png,
                                                 jpegQuality: 90, autoJPEGQuality: 60) == 90)
    }

    @Test func pngBit24StripsTheAlphaChannel() throws {
        let data = try #require(ImageWriter.data(makeImage(), format: .png, pngBitDepth: .bit24))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(decoded.alphaInfo == .none || decoded.alphaInfo == .noneSkipFirst
                || decoded.alphaInfo == .noneSkipLast)

        let withAlpha = try #require(ImageWriter.data(makeImage(), format: .png, pngBitDepth: .bit32))
        let alphaSource = try #require(CGImageSourceCreateWithData(withAlpha as CFData, nil))
        let alphaDecoded = try #require(CGImageSourceCreateImageAtIndex(alphaSource, 0, nil))
        #expect(alphaDecoded.alphaInfo != .none && alphaDecoded.alphaInfo != .noneSkipFirst
                && alphaDecoded.alphaInfo != .noneSkipLast)
    }

    @Test func gifGrayscaleDropsColor() throws {
        // the red test image becomes gray: equal RGB in every decoded pixel
        let data = try #require(ImageWriter.data(makeImage(), format: .gif, gifQuality: .grayscale))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))

        let context = try #require(CGContext(
            data: nil, width: decoded.width, height: decoded.height,
            bitsPerComponent: 8, bytesPerRow: decoded.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
        let pixels = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
        #expect(pixels[0] == pixels[1] && pixels[1] == pixels[2])
    }

    @Test func thumbnailScalesProportionally() throws {
        let image = makeImage(width: 400, height: 200)
        // width-only box (the C# default 200×0) derives height from aspect
        let thumb = try #require(ImageWriter.thumbnail(image, width: 200, height: 0))
        #expect(thumb.width == 200)
        #expect(thumb.height == 100)
        // both dimensions: fit inside the box, aspect kept
        let boxed = try #require(ImageWriter.thumbnail(image, width: 100, height: 100))
        #expect(boxed.width == 100)
        #expect(boxed.height == 50)
    }

    @Test func thumbnailRespectsOnlyIfLarger() throws {
        let small = makeImage(width: 100, height: 50)
        #expect(ImageWriter.thumbnail(small, width: 200, height: 0, onlyIfLarger: true) == nil)
        // default keeps C# ThumbnailCheckSize=false behavior: return as-is
        let asIs = try #require(ImageWriter.thumbnail(small, width: 200, height: 0))
        #expect(asIs.width == 100)
        #expect(ImageWriter.thumbnail(small, width: 0, height: 0) == nil)
    }
}

struct RegionSelectionTests {
    private func solidImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func alpha(of image: CGImage, x: Int, y: Int) -> UInt8 {
        let context = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = context.data!.assumingMemoryBound(to: UInt8.self)
        return pixels[(y * image.width + x) * 4 + 3]
    }

    @Test func rectangleMaskIsIdentity() {
        let image = solidImage(width: 20, height: 20)
        let selection = RegionSelection(rect: CGRect(x: 0, y: 0, width: 20, height: 20),
                                        shape: .rectangle, freehandPoints: [])
        #expect(selection.applyMask(to: image) === image)
    }

    @Test func ellipseMaskClearsCornersKeepsCenter() {
        let image = solidImage(width: 40, height: 40)
        let selection = RegionSelection(rect: CGRect(x: 100, y: 100, width: 40, height: 40),
                                        shape: .ellipse, freehandPoints: [])
        let masked = selection.applyMask(to: image)
        #expect(alpha(of: masked, x: 1, y: 1) == 0)      // corner outside the ellipse
        #expect(alpha(of: masked, x: 20, y: 20) == 255)  // center inside
    }

    @Test func freehandMaskFollowsPolygon() {
        // triangle occupying the left half of a selection at global (100, 100)
        let image = solidImage(width: 40, height: 40)
        let selection = RegionSelection(
            rect: CGRect(x: 100, y: 100, width: 40, height: 40),
            shape: .freehand,
            freehandPoints: [CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 140), CGPoint(x: 120, y: 120)]
        )
        let masked = selection.applyMask(to: image)
        #expect(alpha(of: masked, x: 3, y: 20) == 255)  // deep inside the triangle
        #expect(alpha(of: masked, x: 38, y: 20) == 0)   // right half is outside
    }
}
