// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
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

    public static func data(_ image: CGImage, format: ImageFileFormat, jpegQuality: Int = 90) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            return nil
        }
        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = Double(jpegQuality) / 100
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    public static func write(_ image: CGImage, to url: URL, format: ImageFileFormat = .png, jpegQuality: Int = 90) throws {
        guard let data = data(image, format: format, jpegQuality: jpegQuality) else { throw ImageWriterError.encodingFailed }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
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
