// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Image metadata viewer/stripper. C# shells out to exiftool; Image I/O
// reads the same property groups and can drop them on rewrite.

import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageMetadata {
    public enum MetadataError: LocalizedError {
        case unreadable, unwritable

        public var errorDescription: String? {
            switch self {
            case .unreadable: return "The file could not be read as an image."
            case .unwritable: return "The image could not be rewritten."
            }
        }
    }

    /// Tab-separated "Group⇥Key⇥Value" lines like `exiftool -G -t`.
    public static func describe(url: URL) throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { throw MetadataError.unreadable }
        return lines(from: properties, group: "General").joined(separator: "\n")
    }

    /// Rewrites the file in place without EXIF/GPS/TIFF/IPTC/XMP.
    /// ponytail: Image I/O may recompress lossy formats on rewrite; exiftool's
    /// byte-exact strip would need bundling exiftool.
    public static func strip(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source)
        else { throw MetadataError.unreadable }

        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".sharex-strip-\(UUID().uuidString)")
        let count = CGImageSourceGetCount(source)
        guard let destination = CGImageDestinationCreateWithURL(temp as CFURL, type, count, nil) else {
            throw MetadataError.unwritable
        }
        // a null value deletes the whole property group on copy
        // (NSNull is toll-free bridged to the kCFNull ImageIO expects)
        let removals: [CFString: Any] = [
            kCGImagePropertyExifDictionary: NSNull(),
            kCGImagePropertyExifAuxDictionary: NSNull(),
            kCGImagePropertyGPSDictionary: NSNull(),
            kCGImagePropertyTIFFDictionary: NSNull(),
            kCGImagePropertyIPTCDictionary: NSNull(),
            kCGImageMetadataShouldExcludeXMP: true,
            kCGImageMetadataShouldExcludeGPS: true
        ]
        for index in 0..<count {
            CGImageDestinationAddImageFromSource(destination, source, index, removals as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: temp)
            throw MetadataError.unwritable
        }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
    }

    private static func lines(from dict: [String: Any], group: String) -> [String] {
        var result: [String] = []
        for (key, value) in dict.sorted(by: { $0.key < $1.key }) {
            let cleanKey = key.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
            if let nested = value as? [String: Any] {
                result += lines(from: nested, group: cleanKey)
            } else {
                result.append("\(group)\t\(cleanKey)\t\(value)")
            }
        }
        return result
    }
}
