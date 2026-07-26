// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Drawing effects: backgrounds, borders, checkerboards and watermarks
// (image, text, particles). Text runs through EffectsEnvironment.textParser
// so the app can inject the ShareX name-pattern parser.

import AppKit
import CoreGraphics

public enum EffectsEnvironment {
    /// Hook for %-pattern substitution in watermark text (injected by the app).
    public nonisolated(unsafe) static var textParser: @Sendable (String) -> String = { $0 }
}

public struct DrawBackgroundEffect: ImageEffecting {
    public static let typeName = "DrawBackground"
    public static let category = EffectCategory.drawings
    public var enabled = true
    public var name = ""
    public var color = CSColor.black
    public var useGradient = false
    public var gradient = GradientInfo()
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        EffectDraw.render(width: image.width, height: image.height) { context in
            let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            if useGradient, gradient.isValid {
                gradient.fill(rect, in: context)
            } else {
                context.setFillColor(color.cgColor)
                context.fill(rect)
            }
            EffectDraw.draw(image, in: rect, context: context)
        } ?? image
    }
}

public struct DrawBackgroundImageEffect: ImageEffecting {
    public static let typeName = "DrawBackgroundImage"
    public static let category = EffectCategory.drawings
    public var enabled = true
    public var name = ""
    public var imageFilePath = ""
    public var center = true
    public var tile = false
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard let background = EffectAssets.loadImage(imageFilePath) else { return image }
        return EffectDraw.render(width: image.width, height: image.height) { context in
            let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            if tile {
                EffectAssets.tile(background, in: rect, context: context)
            } else if center {
                EffectDraw.draw(background, in: CGRect(x: (image.width - background.width) / 2,
                                                       y: (image.height - background.height) / 2,
                                                       width: background.width, height: background.height),
                                context: context)
            } else {
                EffectDraw.draw(background, in: rect, context: context)
            }
            EffectDraw.draw(image, in: rect, context: context)
        } ?? image
    }
}

public struct DrawBorderEffect: ImageEffecting {
    public static let typeName = "DrawBorder"
    public static let category = EffectCategory.drawings
    public var enabled = true
    public var name = ""
    /// 0 = Outside, 1 = Inside.
    public var type = 0
    public var size = 1
    public var dashStyle = DashStyle.solid
    public var color = CSColor.black
    public var useGradient = false
    public var gradient = GradientInfo()
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard size > 0 else { return image }
        let grow = type == 0 ? size : 0
        let width = image.width + grow * 2
        let height = image.height + grow * 2
        return EffectDraw.render(width: width, height: height) { context in
            EffectDraw.draw(image, in: CGRect(x: grow, y: grow, width: image.width, height: image.height),
                            context: context)
            // GDI pen with Inset alignment: stroke centered on an inset rect
            let inset = CGFloat(size) / 2
            let strokeRect = CGRect(x: inset, y: inset,
                                    width: CGFloat(width) - CGFloat(size),
                                    height: CGFloat(height) - CGFloat(size))
            context.setLineWidth(CGFloat(size))
            context.setLineDash(phase: 0, lengths: dashStyle.pattern(width: CGFloat(size)))
            if useGradient, gradient.isValid {
                context.saveGState()
                context.addRect(strokeRect)
                context.replacePathWithStrokedPath()
                context.clip()
                gradient.fill(CGRect(x: 0, y: 0, width: width, height: height), in: context)
                context.restoreGState()
            } else {
                context.setStrokeColor(color.cgColor)
                context.stroke(strokeRect)
            }
        } ?? image
    }
}

public struct DrawCheckerboardEffect: ImageEffecting {
    public static let typeName = "DrawCheckerboard"
    public static let category = EffectCategory.drawings
    public var enabled = true
    public var name = ""
    public var size = 10
    public var color = CSColor.lightGray
    public var color2 = CSColor.white
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard size > 0 else { return image }
        return EffectDraw.render(width: image.width, height: image.height) { context in
            context.setFillColor(color2.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.setFillColor(color.cgColor)
            for y in stride(from: 0, to: image.height, by: size) {
                for x in stride(from: 0, to: image.width, by: size) where (x / size + y / size) % 2 == 0 {
                    context.fill(CGRect(x: x, y: y, width: size, height: size))
                }
            }
            EffectDraw.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                            context: context)
        } ?? image
    }
}

public struct DrawImageEffect: ImageEffecting {
    public static let typeName = "DrawImage"
    public static let category = EffectCategory.drawings
    public var enabled = true
    public var name = ""
    public var imageLocation = ""
    public var placement = ContentAlignment.topLeft
    public var offset = CSPoint()
    /// 0 = DontResize, 1 = AbsoluteSize, 2 = PercentageOfWatermark, 3 = PercentageOfCanvas.
    public var sizeMode = 0
    public var size = CSSize()
    /// System.Drawing RotateFlipType subset (see ImageRotateFlipType).
    public var rotateFlip = 0
    public var tile = false
    public var autoHide = false
    public var interpolationMode = 2 // HighQualityBicubic; kept for round-trip
    public var compositingMode = 0   // SourceOver; kept for round-trip
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard var watermark = EffectAssets.loadImage(imageLocation) else { return image }
        watermark = EffectAssets.rotateFlip(watermark, type: rotateFlip)

        var targetSize = CGSize(width: watermark.width, height: watermark.height)
        switch sizeMode {
        case 1 where size.width > 0 && size.height > 0:
            targetSize = CGSize(width: size.width, height: size.height)
        case 2 where size.width > 0:
            targetSize = CGSize(width: CGFloat(watermark.width) * CGFloat(size.width) / 100,
                                height: CGFloat(watermark.height) * CGFloat(size.height > 0 ? size.height : size.width) / 100)
        case 3 where size.width > 0:
            let scale = min(CGFloat(image.width) * CGFloat(size.width) / 100 / CGFloat(watermark.width),
                            CGFloat(image.height) * CGFloat(size.width) / 100 / CGFloat(watermark.height))
            targetSize = CGSize(width: CGFloat(watermark.width) * scale, height: CGFloat(watermark.height) * scale)
        default:
            break
        }
        if autoHide, targetSize.width > CGFloat(image.width) || targetSize.height > CGFloat(image.height) {
            return image
        }
        return EffectDraw.render(width: image.width, height: image.height) { context in
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            EffectDraw.draw(image, in: bounds, context: context)
            if tile {
                EffectAssets.tile(watermark, in: bounds, context: context)
            } else {
                let origin = placement.origin(of: targetSize, in: bounds.size, offset: offset)
                EffectDraw.draw(watermark, in: CGRect(origin: origin, size: targetSize), context: context)
            }
        } ?? image
    }
}

public struct DrawParticlesEffect: ImageEffecting {
    public static let typeName = "DrawParticles"
    public static let category = EffectCategory.drawings
    public var enabled = true
    public var name = ""
    public var imageFolder = ""
    public var imageCount = 1
    public var background = false
    public var randomSize = false
    public var randomSizeMin = 64
    public var randomSizeMax = 128
    public var randomAngle = false
    public var randomAngleMin = 0
    public var randomAngleMax = 360
    public var randomOpacity = false
    public var randomOpacityMin = 0
    public var randomOpacityMax = 100
    public var noOverlap = false
    public var noOverlapOffset = 0
    public var edgeOverlap = false
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        let folder = NSString(string: imageFolder).expandingTildeInPath
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return image }
        let images = files
            .filter { ["png", "jpg", "jpeg", "gif", "bmp", "tiff"].contains(($0 as NSString).pathExtension.lowercased()) }
            .compactMap { EffectAssets.loadImage((folder as NSString).appendingPathComponent($0)) }
        guard !images.isEmpty, imageCount > 0 else { return image }

        var placed: [CGRect] = []
        return EffectDraw.render(width: image.width, height: image.height) { context in
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            if !background {
                EffectDraw.draw(image, in: bounds, context: context)
            }
            for _ in 0..<imageCount {
                guard let particle = images.randomElement() else { break }
                var size = CGSize(width: particle.width, height: particle.height)
                if randomSize, randomSizeMax >= randomSizeMin, randomSizeMin > 0 {
                    let target = CGFloat(Int.random(in: randomSizeMin...randomSizeMax))
                    let scale = target / max(size.width, size.height)
                    size = CGSize(width: size.width * scale, height: size.height * scale)
                }
                let xRange = edgeOverlap ? (-size.width)...CGFloat(image.width) : 0...max(0, CGFloat(image.width) - size.width)
                let yRange = edgeOverlap ? (-size.height)...CGFloat(image.height) : 0...max(0, CGFloat(image.height) - size.height)
                var rect = CGRect(x: CGFloat.random(in: xRange), y: CGFloat.random(in: yRange), size: size)
                if noOverlap {
                    var attempts = 0
                    let inflated = { (r: CGRect) in r.insetBy(dx: CGFloat(-self.noOverlapOffset), dy: CGFloat(-self.noOverlapOffset)) }
                    while attempts < 100, placed.contains(where: { inflated($0).intersects(rect) }) {
                        rect.origin = CGPoint(x: CGFloat.random(in: xRange), y: CGFloat.random(in: yRange))
                        attempts += 1
                    }
                    if attempts == 100 { continue }
                }
                placed.append(rect)
                context.saveGState()
                if randomOpacity, randomOpacityMax >= randomOpacityMin {
                    context.setAlpha(CGFloat(Int.random(in: randomOpacityMin...randomOpacityMax)) / 100)
                }
                if randomAngle, randomAngleMax >= randomAngleMin {
                    let angle = CGFloat(Int.random(in: randomAngleMin...randomAngleMax)) * .pi / 180
                    context.translateBy(x: rect.midX, y: rect.midY)
                    context.rotate(by: angle)
                    context.translateBy(x: -rect.midX, y: -rect.midY)
                }
                EffectDraw.draw(particle, in: rect, context: context)
                context.restoreGState()
            }
            if background {
                EffectDraw.draw(image, in: bounds, context: context)
            }
        } ?? image
    }
}

public struct DrawTextEffect: ImageEffecting {
    public static let typeName = "DrawText"
    public static let category = EffectCategory.drawings
    public var enabled = true
    public var name = ""
    public var text = "Text watermark"
    public var placement = ContentAlignment.bottomRight
    public var offset = CSPoint(x: 5, y: 5)
    public var autoHide = false
    public var textFont = CSFont()
    public var textColor = CSColor(r: 235, g: 235, b: 235)
    public var drawTextShadow = true
    public var textShadowColor = CSColor.black
    public var textShadowOffset = CSPoint(x: -1, y: -1)
    public var cornerRadius = 4
    public var padding = CSPadding(left: 5, top: 5, right: 5, bottom: 5)
    public var drawBorder = true
    public var borderColor = CSColor.black
    public var borderSize = 1
    public var drawBackground = true
    public var backgroundColor = CSColor(r: 42, g: 47, b: 56)
    public var useGradient = false
    public var gradient = GradientInfo.defaultText
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        let parsed = EffectsEnvironment.textParser(text)
        guard !parsed.isEmpty, textFont.size >= 1 else { return image }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: textFont.nsFont,
            .foregroundColor: textColor.nsColor
        ]
        let textSize = parsed.size(withAttributes: attributes)
        let boxSize = CGSize(width: textSize.width + CGFloat(padding.horizontal),
                             height: textSize.height + CGFloat(padding.vertical))
        if autoHide, boxSize.width > CGFloat(image.width) || boxSize.height > CGFloat(image.height) {
            return image
        }
        return EffectDraw.render(width: image.width, height: image.height) { context in
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            EffectDraw.draw(image, in: bounds, context: context)

            let origin = placement.origin(of: boxSize, in: bounds.size, offset: offset)
            let box = CGRect(origin: origin, size: boxSize)
            let path = CGPath(roundedRect: box,
                              cornerWidth: min(CGFloat(cornerRadius), box.width / 2),
                              cornerHeight: min(CGFloat(cornerRadius), box.height / 2), transform: nil)
            if drawBackground {
                if useGradient, gradient.isValid {
                    context.saveGState()
                    context.addPath(path)
                    context.clip()
                    gradient.fill(box, in: context)
                    context.restoreGState()
                } else {
                    context.setFillColor(backgroundColor.cgColor)
                    context.addPath(path)
                    context.fillPath()
                }
            }
            if drawBorder, borderSize > 0 {
                context.setStrokeColor(borderColor.cgColor)
                context.setLineWidth(CGFloat(borderSize))
                context.addPath(path)
                context.strokePath()
            }

            let graphics = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            let textOrigin = CGPoint(x: box.minX + CGFloat(padding.left), y: box.minY + CGFloat(padding.top))
            if drawTextShadow {
                var shadowAttributes = attributes
                shadowAttributes[.foregroundColor] = textShadowColor.nsColor
                parsed.draw(at: CGPoint(x: textOrigin.x + CGFloat(textShadowOffset.x),
                                        y: textOrigin.y + CGFloat(textShadowOffset.y)),
                            withAttributes: shadowAttributes)
            }
            parsed.draw(at: textOrigin, withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
        } ?? image
    }
}

public struct DrawTextExEffect: ImageEffecting {
    public static let typeName = "DrawTextEx"
    public static let category = EffectCategory.drawings
    public var enabled = true
    public var name = ""
    public var text = "Text"
    public var placement = ContentAlignment.topLeft
    public var offset = CSPoint()
    public var angle = 0
    public var autoHide = false
    public var textFont = CSFont(family: "Arial", size: 40)
    public var color = CSColor(r: 235, g: 235, b: 235)
    public var useGradient = false
    public var gradient = GradientInfo()
    public var outline = false
    public var outlineSize = 5
    public var outlineColor = CSColor(r: 235, g: 0, b: 0)
    public var shadow = false
    public var shadowOffset = CSPoint(x: 0, y: 5)
    public var shadowColor = CSColor(r: 0, g: 0, b: 0, a: 125)
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        let parsed = EffectsEnvironment.textParser(text)
        guard !parsed.isEmpty, textFont.size >= 1 else { return image }
        let font = textFont.nsFont
        let textSize = parsed.size(withAttributes: [.font: font])
        if autoHide, textSize.width > CGFloat(image.width) || textSize.height > CGFloat(image.height) {
            return image
        }
        return EffectDraw.render(width: image.width, height: image.height) { context in
            let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            EffectDraw.draw(image, in: bounds, context: context)

            let origin = placement.origin(of: textSize, in: bounds.size, offset: offset)
            let graphics = NSGraphicsContext(cgContext: context, flipped: true)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            if angle != 0 {
                let center = CGPoint(x: origin.x + textSize.width / 2, y: origin.y + textSize.height / 2)
                context.translateBy(x: center.x, y: center.y)
                context.rotate(by: CGFloat(angle) * .pi / 180)
                context.translateBy(x: -center.x, y: -center.y)
            }
            if shadow {
                let shadowPoint = CGPoint(x: origin.x + CGFloat(shadowOffset.x),
                                          y: origin.y + CGFloat(shadowOffset.y))
                parsed.draw(at: shadowPoint, withAttributes: [.font: font, .foregroundColor: shadowColor.nsColor])
            }
            if outline, outlineSize > 0 {
                // stroke pass behind the fill
                parsed.draw(at: origin, withAttributes: [
                    .font: font,
                    .strokeColor: outlineColor.nsColor,
                    .strokeWidth: CGFloat(outlineSize) * 2 // NSAttributedString stroke width is % of font size
                ])
            }
            if useGradient, gradient.isValid {
                // draw text as clip mask, then fill with the gradient
                context.saveGState()
                let textRect = CGRect(origin: origin, size: textSize)
                context.setTextDrawingMode(.clip)
                parsed.draw(at: origin, withAttributes: [.font: font, .foregroundColor: NSColor.black])
                gradient.fill(textRect, in: context)
                context.restoreGState()
            } else {
                parsed.draw(at: origin, withAttributes: [.font: font, .foregroundColor: color.nsColor])
            }
            NSGraphicsContext.restoreGraphicsState()
        } ?? image
    }
}

// MARK: - Asset helpers

enum EffectAssets {
    static func loadImage(_ path: String) -> CGImage? {
        guard !path.isEmpty else { return nil }
        let expanded = NSString(string: path).expandingTildeInPath
        guard let image = NSImage(contentsOfFile: expanded) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    static func tile(_ image: CGImage, in bounds: CGRect, context: CGContext) {
        for y in stride(from: 0, to: Int(bounds.height), by: image.height) {
            for x in stride(from: 0, to: Int(bounds.width), by: image.width) {
                EffectDraw.draw(image, in: CGRect(x: x, y: y, width: image.width, height: image.height),
                                context: context)
            }
        }
    }

    /// System.Drawing RotateFlipType: rotations are clockwise.
    static func rotateFlip(_ image: CGImage, type: Int) -> CGImage {
        guard type != 0 else { return image }
        let rotation = type & 3            // 0/1/2/3 -> 0/90/180/270 clockwise
        let flipX = type & 4 != 0
        let swap = rotation % 2 == 1
        let width = swap ? image.height : image.width
        let height = swap ? image.width : image.height
        return EffectDraw.render(width: width, height: height) { context in
            context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
            context.rotate(by: CGFloat(rotation) * .pi / 2)
            if flipX {
                context.scaleBy(x: -1, y: 1)
            }
            EffectDraw.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2,
                                              width: image.width, height: image.height), context: context)
        } ?? image
    }
}

private extension CGRect {
    init(x: CGFloat, y: CGFloat, size: CGSize) {
        self.init(x: x, y: y, width: size.width, height: size.height)
    }
}
