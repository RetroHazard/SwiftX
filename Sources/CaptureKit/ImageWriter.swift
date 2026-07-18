// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum ImageWriterError: LocalizedError {
    case encodingFailed

    public var errorDescription: String? { "Failed to encode the image." }
}

/// Screenshot output formats; raw values match the C# EImageFormat enum names
/// stored in TaskSettings.json ("ImageFormat": "PNG").
public enum ImageFileFormat: String, CaseIterable, Sendable {
    case png = "PNG"
    case jpeg = "JPEG"
    case gif = "GIF"
    case bmp = "BMP"
    case tiff = "TIFF"

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .gif: "gif"
        case .bmp: "bmp"
        case .tiff: "tiff"
        }
    }

    public var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .gif: .gif
        case .bmp: .bmp
        case .tiff: .tiff
        }
    }

    public var mimeType: String {
        utType.preferredMIMEType ?? "application/octet-stream"
    }
}

/// PNG output depth; raw values match the C# PNGBitDepth enum names.
/// Bit24 strips the alpha channel (smaller files, opaque background).
public enum PNGBitDepth: String, CaseIterable, Sendable {
    case `default` = "Default"
    case bit32 = "Bit32"
    case bit24 = "Bit24"
}

/// GIF palette mode; raw values match the C# GIFQuality enum names.
/// ImageIO always quantizes to a 256-color palette, so Bit8 equals Default
/// and Bit4 falls back to it; Grayscale converts before encoding.
public enum GIFQuality: String, CaseIterable, Sendable {
    case `default` = "Default"
    case bit8 = "Bit8"
    case bit4 = "Bit4"
    case grayscale = "Grayscale"
}

public enum ImageWriter {
    /// Resolves the configured format, honoring C#'s ImageAutoUseJPEG:
    /// large captures switch to JPEG so wallpaper-sized PNGs don't hit hosts.
    public static func effectiveFormat(
        named name: String, autoUseJPEG: Bool, autoUseJPEGSize: Int,
        width: Int, height: Int
    ) -> ImageFileFormat {
        let format = ImageFileFormat(rawValue: name) ?? .png
        if format != .jpeg, autoUseJPEG, max(width, height) > autoUseJPEGSize {
            return .jpeg
        }
        return format
    }

    /// C# ImageAutoJPEGQuality: when the auto-JPEG size rule forced JPEG,
    /// its own quality setting applies instead of the regular one.
    public static func effectiveJPEGQuality(
        configuredFormatName: String, effectiveFormat: ImageFileFormat,
        jpegQuality: Int, autoJPEGQuality: Int
    ) -> Int {
        effectiveFormat == .jpeg && ImageFileFormat(rawValue: configuredFormatName) != .jpeg
            ? autoJPEGQuality : jpegQuality
    }

    public static func data(
        _ image: CGImage, format: ImageFileFormat, jpegQuality: Int = 90,
        pngBitDepth: PNGBitDepth = .default, gifQuality: GIFQuality = .default
    ) -> Data? {
        var source = image
        if format == .png {
            switch pngBitDepth {
            case .bit24: source = redrawn(image, includeAlpha: false) ?? image
            case .bit32 where image.alphaInfo == .none || image.alphaInfo == .noneSkipFirst
                || image.alphaInfo == .noneSkipLast:
                source = redrawn(image, includeAlpha: true) ?? image
            default: break
            }
        }
        if format == .gif, gifQuality == .grayscale {
            source = grayscale(image) ?? image
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = Double(jpegQuality) / 100
        }
        CGImageDestinationAddImage(destination, source, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    public static func write(
        _ image: CGImage, to url: URL, format: ImageFileFormat = .png, jpegQuality: Int = 90,
        pngBitDepth: PNGBitDepth = .default, gifQuality: GIFQuality = .default
    ) throws {
        guard let data = data(image, format: format, jpegQuality: jpegQuality,
                              pngBitDepth: pngBitDepth, gifQuality: gifQuality) else {
            throw ImageWriterError.encodingFailed
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Redraws into an sRGB context with or without an alpha channel.
    private static func redrawn(_ image: CGImage, includeAlpha: Bool) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: (includeAlpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue
        ) else { return nil }
        if !includeAlpha {
            // transparent areas flatten onto white, like GDI+ drawing on a blank bitmap
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func grayscale(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    public static func pngData(_ image: CGImage) -> Data? {
        data(image, format: .png)
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        try write(image, to: url, format: .png)
    }

    /// Scales the image to fit a thumbnail box, keeping aspect ratio.
    /// A zero width or height is derived from the other side (C# thumbnail
    /// settings default to 200×0). `onlyIfLarger` mirrors C# ThumbnailCheckSize:
    /// true skips images that already fit the box; false returns them as-is.
    public static func thumbnail(_ image: CGImage, width: Int, height: Int, onlyIfLarger: Bool = false) -> CGImage? {
        guard width > 0 || height > 0, image.width > 0, image.height > 0 else { return nil }
        let aspect = CGFloat(image.width) / CGFloat(image.height)

        var targetWidth = CGFloat(width)
        var targetHeight = CGFloat(height)
        if targetWidth <= 0 { targetWidth = targetHeight * aspect }
        if targetHeight <= 0 { targetHeight = targetWidth / aspect }
        // fit inside the box without stretching or upscaling
        let scale = min(targetWidth / CGFloat(image.width), targetHeight / CGFloat(image.height))
        guard scale < 1 else { return onlyIfLarger ? nil : image }

        let size = CGSize(width: max(1, (CGFloat(image.width) * scale).rounded()),
                          height: max(1, (CGFloat(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    @MainActor
    public static func copyToClipboard(_ image: CGImage) {
        guard let data = pngData(image) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }
}
