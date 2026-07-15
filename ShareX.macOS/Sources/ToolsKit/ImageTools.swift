// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Combine / split geometry for the image tools, mirroring C#'s
// ImageCombinerOptions (orientation, alignment, spacing, wrap) and
// ImageSplitterForm (rows × columns grid).

import CoreGraphics

public enum ImageCombineOrientation: String, CaseIterable, Sendable {
    case horizontal = "Horizontal"
    case vertical = "Vertical"
}

public enum ImageCombineAlignment: String, CaseIterable, Sendable {
    case leadingOrTop = "Left / Top"
    case center = "Center"
    case trailingOrBottom = "Right / Bottom"
}

public enum ImageTools {
    /// Joins images along `orientation`; `wrapAfter` > 0 chunks first and
    /// joins the chunks along the other axis (C# WrapAfter).
    public static func combine(_ images: [CGImage],
                               orientation: ImageCombineOrientation,
                               alignment: ImageCombineAlignment = .leadingOrTop,
                               spacing: Int = 0,
                               wrapAfter: Int = 0) -> CGImage? {
        guard !images.isEmpty else { return nil }
        if images.count == 1 { return images[0] }

        if wrapAfter > 0, images.count > wrapAfter {
            let chunks = stride(from: 0, to: images.count, by: wrapAfter).compactMap { start in
                combine(Array(images[start..<min(start + wrapAfter, images.count)]),
                        orientation: orientation, alignment: alignment, spacing: spacing)
            }
            let crossOrientation: ImageCombineOrientation = orientation == .horizontal ? .vertical : .horizontal
            return combine(chunks, orientation: crossOrientation, alignment: alignment, spacing: spacing)
        }

        let totalSpacing = spacing * (images.count - 1)
        let width: Int
        let height: Int
        switch orientation {
        case .horizontal:
            width = images.map(\.width).reduce(0, +) + totalSpacing
            height = images.map(\.height).max() ?? 0
        case .vertical:
            width = images.map(\.width).max() ?? 0
            height = images.map(\.height).reduce(0, +) + totalSpacing
        }
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        var cursor = 0
        for image in images {
            let rect: CGRect
            switch orientation {
            case .horizontal:
                // CG origin is bottom-left; "top" alignment means y = height - h
                let y: Int
                switch alignment {
                case .leadingOrTop: y = height - image.height
                case .center: y = (height - image.height) / 2
                case .trailingOrBottom: y = 0
                }
                rect = CGRect(x: cursor, y: y, width: image.width, height: image.height)
                cursor += image.width + spacing
            case .vertical:
                let x: Int
                switch alignment {
                case .leadingOrTop: x = 0
                case .center: x = (width - image.width) / 2
                case .trailingOrBottom: x = width - image.width
                }
                // first image lands at the visual top
                cursor += image.height
                rect = CGRect(x: x, y: height - cursor, width: image.width, height: image.height)
                cursor += spacing
            }
            context.draw(image, in: rect)
        }
        return context.makeImage()
    }

    /// Row-major tiles (left→right, top→bottom). Remainder pixels go to the
    /// last row/column, like integer-dividing users expect.
    public static func split(_ image: CGImage, rows: Int, columns: Int) -> [CGImage] {
        guard rows > 0, columns > 0 else { return [] }
        let tileWidth = image.width / columns
        let tileHeight = image.height / rows
        guard tileWidth > 0, tileHeight > 0 else { return [] }

        var tiles: [CGImage] = []
        for row in 0..<rows {
            for column in 0..<columns {
                // cropping(to:) takes top-left pixel coordinates
                let width = column == columns - 1 ? image.width - column * tileWidth : tileWidth
                let height = row == rows - 1 ? image.height - row * tileHeight : tileHeight
                let rect = CGRect(x: column * tileWidth, y: row * tileHeight, width: width, height: height)
                if let tile = image.cropping(to: rect) {
                    tiles.append(tile)
                }
            }
        }
        return tiles
    }
}
