// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Filter effects: convolution kernels from ConvolutionMatrixManager plus the
// ImageHelpers drawing algorithms (torn/wavy edges, slice, reflection, shadow, glow).

import CoreGraphics
import Foundation

public struct BlurEffect: ImageEffecting {
    public static let typeName = "Blur"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public var radius = 15
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.boxBlur(image, range: radius)
    }
}

public struct ColorDepthEffect: ImageEffecting {
    public static let typeName = "ColorDepth"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public var bitsPerChannel = 4
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.colorDepth(image, bitsPerChannel: bitsPerChannel)
    }
}

public struct EdgeDetectEffect: ImageEffecting {
    public static let typeName = "EdgeDetect"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.convolve(image, kernel: [[-1, -1, -1], [0, 0, 0], [1, 1, 1]], offset: 127)
    }
}

public struct EmbossEffect: ImageEffecting {
    public static let typeName = "Emboss"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.convolve(image, kernel: [[-1, 0, -1], [0, 4, 0], [-1, 0, -1]], offset: 127)
    }
}

public struct GaussianBlurEffect: ImageEffecting {
    public static let typeName = "GaussianBlur"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public var radius = 15
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard radius > 0 else { return image }
        let size = radius * 2 + 1
        let kernel = PixelOps.gaussianKernel(size: size, sigma: Double(radius) / 3)
        let horizontal = PixelOps.convolve(image, kernel: [kernel], considerAlpha: true)
        return PixelOps.convolve(horizontal, kernel: kernel.map { [$0] }, considerAlpha: true)
    }
}

public struct GlowEffect: ImageEffecting {
    public static let typeName = "Glow"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public var size = 20
    public var strength: Float = 1
    public var color = CSColor.white
    public var useGradient = false
    public var gradient = GradientInfo()
    public var offset = CSPoint()
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard size >= 0, strength >= 0.1 else { return image }
        var blurred = image
        if size > 0 {
            let pad = CSPadding(left: size, top: size, right: size, bottom: size)
            blurred = PixelOps.boxBlur(EffectDraw.addCanvas(image, margin: pad), range: size)
        }
        let mask: CGImage
        if useGradient, gradient.isValid {
            mask = gradientMask(of: blurred)
        } else {
            mask = PixelOps.mask(blurred, opacity: strength, color: color)
        }
        let width = mask.width + abs(offset.x)
        let height = mask.height + abs(offset.y)
        return EffectDraw.render(width: width, height: height) { context in
            EffectDraw.draw(mask, in: CGRect(x: max(0, offset.x), y: max(0, offset.y),
                                             width: mask.width, height: mask.height), context: context)
            EffectDraw.draw(image, in: CGRect(x: max(size, -offset.x + size), y: max(size, -offset.y + size),
                                              width: image.width, height: image.height), context: context)
        } ?? image
    }

    /// ImageHelpers.CreateGradientMask: gradient colors, alpha = source alpha * strength.
    private func gradientMask(of source: CGImage) -> CGImage {
        let colored = EffectDraw.render(width: source.width, height: source.height) { context in
            gradient.fill(CGRect(x: 0, y: 0, width: source.width, height: source.height), in: context)
        } ?? source
        // multiply gradient alpha by source alpha * strength
        guard let gradientBuffer = PixelBuffer(image: colored),
              let sourceBuffer = PixelBuffer(image: source) else { return colored }
        var result = gradientBuffer
        for i in stride(from: 0, to: result.pixels.count, by: 4) {
            let a = Double(sourceBuffer.pixels[i + 3]) * Double(gradientBuffer.pixels[i + 3]) / 255 * Double(strength)
            result.pixels[i + 3] = UInt8(max(0, min(255, a)))
        }
        return result.makeImage() ?? colored
    }
}

public struct MatrixConvolutionEffect: ImageEffecting {
    public static let typeName = "MatrixConvolution"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public var x0Y0 = 0, x1Y0 = 0, x2Y0 = 0
    public var x0Y1 = 0, x1Y1 = 1, x2Y1 = 0
    public var x0Y2 = 0, x1Y2 = 0, x2Y2 = 0
    public var factor: Double = 1
    public var offset = 0
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard factor != 0 else { return image }
        let kernel = [
            [Double(x0Y0) / factor, Double(x1Y0) / factor, Double(x2Y0) / factor],
            [Double(x0Y1) / factor, Double(x1Y1) / factor, Double(x2Y1) / factor],
            [Double(x0Y2) / factor, Double(x1Y2) / factor, Double(x2Y2) / factor]
        ]
        return PixelOps.convolve(image, kernel: kernel, offset: Double(offset))
    }
}

public struct MeanRemovalEffect: ImageEffecting {
    public static let typeName = "MeanRemoval"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        // weight 9, factor = weight - 8 = 1
        PixelOps.convolve(image, kernel: [[-1, -1, -1], [-1, 9, -1], [-1, -1, -1]])
    }
}

public struct OutlineEffect: ImageEffecting {
    public static let typeName = "Outline"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public var size = 1
    public var padding = 0
    public var color = CSColor.black
    public var outlineOnly = false
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard let outline = PixelOps.outline(image, minRadius: padding,
                                             maxRadius: padding + size + 1, color: color)
        else { return image }
        if outlineOnly { return outline }
        return EffectDraw.render(width: image.width, height: image.height) { context in
            let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            EffectDraw.draw(image, in: rect, context: context)
            EffectDraw.draw(outline, in: rect, context: context)
        } ?? image
    }
}

public struct PixelateEffect: ImageEffecting {
    public static let typeName = "Pixelate"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public var size = 10
    public var borderSize = 0
    public var borderColor = CSColor.black
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        let pixelated = PixelOps.pixelate(image, size: size)
        guard size > 1, borderSize > 0, borderColor.a > 0 else { return pixelated }
        return EffectDraw.render(width: image.width, height: image.height) { context in
            EffectDraw.draw(pixelated, in: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                            context: context)
            context.setStrokeColor(borderColor.cgColor)
            context.setLineWidth(CGFloat(borderSize))
            // inset grid lines on every block boundary
            for x in stride(from: 0, through: image.width, by: size) {
                context.move(to: CGPoint(x: CGFloat(x) + CGFloat(borderSize) / 2, y: 0))
                context.addLine(to: CGPoint(x: CGFloat(x) + CGFloat(borderSize) / 2, y: CGFloat(image.height)))
            }
            for y in stride(from: 0, through: image.height, by: size) {
                context.move(to: CGPoint(x: 0, y: CGFloat(y) + CGFloat(borderSize) / 2))
                context.addLine(to: CGPoint(x: CGFloat(image.width), y: CGFloat(y) + CGFloat(borderSize) / 2))
            }
            context.strokePath()
        } ?? pixelated
    }
}

public struct ReflectionEffect: ImageEffecting {
    public static let typeName = "Reflection"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public var percentage = 20
    public var maxAlpha = 255
    public var minAlpha = 0
    public var offset = 0
    public var skew = false
    public var skewSize = 25
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        let percent = max(1, min(100, percentage))
        let reflectionHeight = Int(Float(image.height) * Float(percent) / 100)
        guard reflectionHeight > 0 else { return image }

        // flipped top slice with a downward alpha ramp: a raw draw inside the
        // flipped context mirrors the image, putting the original's bottom row at y=0
        guard let flipped = EffectDraw.render(width: image.width, height: reflectionHeight, { context in
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }) else { return image }
        var reflection = PixelOps.reflectionAlphaRamp(flipped, maxAlpha: max(0, min(255, maxAlpha)),
                                                      minAlpha: max(0, min(255, minAlpha)))
        if skew {
            reflection = SkewEffect.skewed(reflection, x: skewSize, y: 0)
        }

        return EffectDraw.render(width: reflection.width, height: image.height + reflection.height + offset) { context in
            EffectDraw.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), context: context)
            EffectDraw.draw(reflection, in: CGRect(x: 0, y: image.height + offset,
                                                   width: reflection.width, height: reflection.height), context: context)
        } ?? image
    }
}

public struct RGBSplitEffect: ImageEffecting {
    public static let typeName = "RGBSplit"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public var offsetRed = CSPoint(x: -5, y: 0)
    public var offsetGreen = CSPoint(x: 0, y: 0)
    public var offsetBlue = CSPoint(x: 5, y: 0)
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.rgbSplit(image, red: offsetRed, green: offsetGreen, blue: offsetBlue)
    }
}

public struct ShadowEffect: ImageEffecting {
    public static let typeName = "Shadow"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public var opacity: Float = 0.6
    public var size = 10
    public var darkness: Float = 0
    public var color = CSColor.black
    public var offset = CSPoint()
    public var autoResize = true
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        // silhouette on an enlarged canvas, box-blurred
        let pad = CSPadding(left: size, top: size, right: size, bottom: size)
        var shadow = PixelOps.mask(EffectDraw.addCanvas(image, margin: pad), opacity: opacity, color: color)
        if size > 0 {
            shadow = PixelOps.boxBlur(shadow, range: size)
        }
        if darkness > 1 {
            shadow = PixelOps.colorMatrix(shadow, [
                [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, darkness], [0, 0, 0, 0]
            ])
        }
        if autoResize {
            let width = shadow.width + abs(offset.x)
            let height = shadow.height + abs(offset.y)
            return EffectDraw.render(width: width, height: height) { context in
                EffectDraw.draw(shadow, in: CGRect(x: max(0, offset.x), y: max(0, offset.y),
                                                   width: shadow.width, height: shadow.height), context: context)
                EffectDraw.draw(image, in: CGRect(x: max(size, -offset.x + size), y: max(size, -offset.y + size),
                                                  width: image.width, height: image.height), context: context)
            } ?? image
        }
        return EffectDraw.render(width: image.width, height: image.height) { context in
            EffectDraw.draw(shadow, in: CGRect(x: -size + offset.x, y: -size + offset.y,
                                               width: shadow.width, height: shadow.height), context: context)
            EffectDraw.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), context: context)
        } ?? image
    }
}

public struct SharpenEffect: ImageEffecting {
    public static let typeName = "Sharpen"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        // weight 11, factor = weight - 8 = 3
        let f = 3.0
        return PixelOps.convolve(image, kernel: [
            [0, -2 / f, 0], [-2 / f, 11 / f, -2 / f], [0, -2 / f, 0]
        ])
    }
}

public struct SliceEffect: ImageEffecting {
    public static let typeName = "Slice"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public var minSliceHeight = 10
    public var maxSliceHeight = 100
    public var minSliceShift = 0
    public var maxSliceShift = 10
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard minSliceHeight >= 1, maxSliceHeight >= minSliceHeight else { return image }
        return EffectDraw.render(width: image.width, height: image.height) { context in
            var y = 0
            while y < image.height {
                let sliceHeight = Int.random(in: minSliceHeight...maxSliceHeight)
                let shift = Int.random(in: min(minSliceShift, maxSliceShift)...max(minSliceShift, maxSliceShift))
                let x = Bool.random() ? -shift : shift
                if let slice = image.cropping(to: CGRect(x: 0, y: y, width: image.width,
                                                         height: min(sliceHeight, image.height - y))) {
                    EffectDraw.draw(slice, in: CGRect(x: x, y: y, width: slice.width, height: slice.height),
                                    context: context)
                }
                y += sliceHeight
            }
        } ?? image
    }
}

public struct SmoothEffect: ImageEffecting {
    public static let typeName = "Smooth"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        // weight 1, factor = weight + 8 = 9: uniform 3x3 mean
        let v = 1.0 / 9
        return PixelOps.convolve(image, kernel: [[v, v, v], [v, v, v], [v, v, v]])
    }
}

public struct TornEdgeEffect: ImageEffecting {
    public static let typeName = "TornEdge"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public var depth = 15
    public var range = 20
    public var sides = AnchorSides.all
    public var curvedEdges = true
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard depth >= 1, range >= 1, !sides.isEmpty else { return image }
        let w = image.width, h = image.height
        let horizontalCount = w / range
        let verticalCount = h / range
        guard horizontalCount > 1 || verticalCount > 1 else { return image }

        var points: [CGPoint] = []
        func tooth() -> Int { Int.random(in: 0..<max(1, depth)) }

        if sides.contains(.top), horizontalCount > 1 {
            let startX = (sides.contains(.left) && verticalCount > 1) ? depth : 0
            let endX = (sides.contains(.right) && verticalCount > 1) ? w - depth : w
            for x in stride(from: startX, to: endX, by: range) {
                points.append(CGPoint(x: x, y: tooth()))
            }
        } else {
            points.append(CGPoint(x: 0, y: 0))
            points.append(CGPoint(x: w, y: 0))
        }
        if sides.contains(.right), verticalCount > 1 {
            let startY = (sides.contains(.top) && horizontalCount > 1) ? depth : 0
            let endY = (sides.contains(.bottom) && horizontalCount > 1) ? h - depth : h
            for y in stride(from: startY, to: endY, by: range) {
                points.append(CGPoint(x: w - depth + tooth(), y: y))
            }
        } else {
            points.append(CGPoint(x: w, y: 0))
            points.append(CGPoint(x: w, y: h))
        }
        if sides.contains(.bottom), horizontalCount > 1 {
            let startX = (sides.contains(.right) && verticalCount > 1) ? w - depth : w
            let endX = (sides.contains(.left) && verticalCount > 1) ? depth : 0
            var x = startX
            while x >= endX {
                points.append(CGPoint(x: x, y: h - depth + tooth()))
                x = (x / range - 1) * range
            }
        } else {
            points.append(CGPoint(x: w, y: h))
            points.append(CGPoint(x: 0, y: h))
        }
        if sides.contains(.left), verticalCount > 1 {
            let startY = (sides.contains(.bottom) && horizontalCount > 1) ? h - depth : h
            let endY = (sides.contains(.top) && horizontalCount > 1) ? depth : 0
            var y = startY
            while y >= endY {
                points.append(CGPoint(x: tooth(), y: y))
                y = (y / range - 1) * range
            }
        } else {
            points.append(CGPoint(x: 0, y: h))
            points.append(CGPoint(x: 0, y: 0))
        }

        // drop consecutive duplicates like Distinct() prevents degenerate fills
        var unique: [CGPoint] = []
        for p in points where unique.last != p { unique.append(p) }
        let path = curvedEdges ? EdgePath.closedCurve(through: unique) : EdgePath.polygon(unique)
        return EffectDraw.fillPath(path, with: image)
    }
}

public struct WaveEdgeEffect: ImageEffecting {
    public static let typeName = "WaveEdge"
    public static let category = EffectCategory.filters
    public var enabled = true
    public var name = ""
    public var depth = 15
    public var range = 20
    public var sides = AnchorSides.all
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard depth >= 1, range >= 1, !sides.isEmpty else { return image }
        let w = image.width, h = image.height
        let horizontalWaveCount = max(2, (w / range + 1) / 2 * 2) - 1
        let verticalWaveCount = max(2, (h / range + 1) / 2 * 2) - 1
        let horizontalRange = w / horizontalWaveCount
        let verticalRange = h / verticalWaveCount
        let step = min(max(1, range / depth), 10)

        func wave(_ t: Int, _ max: Int) -> Int {
            Int((1 - cos(Double(t) * .pi / Double(max))) * Double(depth) / 2)
        }

        var points: [CGPoint] = []
        if sides.contains(.top) {
            let startX = sides.contains(.left) ? depth : 0
            let endX = sides.contains(.right) ? w - depth : w
            for x in stride(from: startX, to: endX, by: step) {
                points.append(CGPoint(x: x, y: wave(x, horizontalRange)))
            }
            points.append(CGPoint(x: endX, y: wave(endX, horizontalRange)))
        } else {
            points.append(CGPoint(x: 0, y: 0))
        }
        if sides.contains(.right) {
            let startY = sides.contains(.top) ? depth : 0
            let endY = sides.contains(.bottom) ? h - depth : h
            for y in stride(from: startY, to: endY, by: step) {
                points.append(CGPoint(x: w - depth + wave(y, verticalRange), y: y))
            }
            points.append(CGPoint(x: w - depth + wave(endY, verticalRange), y: endY))
        } else {
            points.append(CGPoint(x: CGFloat(w), y: points.last?.y ?? 0))
        }
        if sides.contains(.bottom) {
            let startX = sides.contains(.right) ? w - depth : w
            let endX = sides.contains(.left) ? depth : 0
            for x in stride(from: startX, through: endX, by: -step) {
                points.append(CGPoint(x: x, y: h - depth + wave(x, horizontalRange)))
            }
            points.append(CGPoint(x: endX, y: h - depth + wave(endX, horizontalRange)))
        } else {
            points.append(CGPoint(x: points.last?.x ?? 0, y: CGFloat(h)))
        }
        if sides.contains(.left) {
            let startY = sides.contains(.bottom) ? h - depth : h
            let endY = sides.contains(.top) ? depth : 0
            for y in stride(from: startY, through: endY, by: -step) {
                points.append(CGPoint(x: wave(y, verticalRange), y: y))
            }
            points.append(CGPoint(x: wave(endY, verticalRange), y: endY))
        } else {
            points.append(CGPoint(x: 0, y: points.last?.y ?? 0))
        }

        return EffectDraw.fillPath(EdgePath.polygon(points), with: image)
    }
}

/// Shared path builders for edge effects.
enum EdgePath {
    static func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard points.count >= 3 else { return path }
        path.addLines(between: points)
        path.closeSubpath()
        return path
    }

    /// GDI+ FillClosedCurve equivalent: closed Catmull-Rom spline (tension 0.5).
    static func closedCurve(through points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        let n = points.count
        guard n >= 3 else { return polygon(points) }
        path.move(to: points[0])
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n]
            let p1 = points[i]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }
}

private extension CGPoint {
    init(x: Int, y: Int) {
        self.init(x: CGFloat(x), y: CGFloat(y))
    }
}
