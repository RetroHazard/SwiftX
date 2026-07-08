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

public enum ImageWriter {
    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    public static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let data = pngData(image) else { throw ImageWriterError.encodingFailed }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    @MainActor
    public static func copyToClipboard(_ image: CGImage) {
        guard let data = pngData(image) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: .png)
    }
}
