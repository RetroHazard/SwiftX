// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import AppKit
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ToolsKit

struct ImageMetadataTests {
    @Test func describesAndStripsEXIF() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sharex-meta-test-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: url) }
        try Self.writeJPEGWithEXIF(to: url)

        let described = try ImageMetadata.describe(url: url)
        #expect(described.contains("SHAREX-TEST-CAMERA"))

        try ImageMetadata.strip(url: url)

        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        #expect(tiff?[kCGImagePropertyTIFFModel as String] == nil)
        #expect(exif?[kCGImagePropertyExifUserComment as String] == nil)

        // the pixels survived
        #expect(ImageLoader.load(url: url) != nil)
    }

    static func writeJPEGWithEXIF(to url: URL) throws {
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let image = context.makeImage()!

        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        )!
        let properties: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "SHAREX-TEST-CAMERA"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "secret comment"]
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
    }
}
