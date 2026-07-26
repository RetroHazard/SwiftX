// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Manipulation effects: canvas/crop/resize geometry, matching the C#
// ImageHelpers semantics (auto-aspect when a dimension is 0, etc).

import CoreGraphics
import Foundation

public struct AutoCropEffect: ImageEffecting {
    public static let typeName = "AutoCrop"
    public static let category = EffectCategory.manipulations
    public var enabled = true
    public var name = ""
    public var sides = AnchorSides.all
    public var padding = 0
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard let buffer = PixelBuffer(image: image) else { return image }
        let w = buffer.width, h = buffer.height
        let reference: [UInt8] = [buffer.pixels[0], buffer.pixels[1], buffer.pixels[2], buffer.pixels[3]]

        func matchesReference(_ i: Int) -> Bool {
            buffer.pixels[i] == reference[0] && buffer.pixels[i + 1] == reference[1]
                && buffer.pixels[i + 2] == reference[2] && buffer.pixels[i + 3] == reference[3]
        }
        func rowUniform(_ y: Int) -> Bool {
            for x in 0..<w where !matchesReference(buffer.index(x, y)) { return false }
            return true
        }
        func columnUniform(_ x: Int) -> Bool {
            for y in 0..<h where !matchesReference(buffer.index(x, y)) { return false }
            return true
        }

        var top = 0, bottom = h, left = 0, right = w
        if sides.contains(.top) { while top < bottom - 1, rowUniform(top) { top += 1 } }
        if sides.contains(.bottom) { while bottom > top + 1, rowUniform(bottom - 1) { bottom -= 1 } }
        if sides.contains(.left) { while left < right - 1, columnUniform(left) { left += 1 } }
        if sides.contains(.right) { while right > left + 1, columnUniform(right - 1) { right -= 1 } }

        guard top > 0 || left > 0 || bottom < h || right < w else { return image }
        guard let cropped = image.cropping(to: CGRect(x: left, y: top, width: right - left, height: bottom - top))
        else { return image }
        if padding > 0 {
            let color = CSColor(r: reference[0], g: reference[1], b: reference[2], a: reference[3])
            return EffectDraw.addCanvas(cropped, margin: CSPadding(left: padding, top: padding,
                                                                   right: padding, bottom: padding), color: color)
        }
        return cropped
    }
}

public struct CanvasEffect: ImageEffecting {
    public static let typeName = "Canvas"
    public static let category = EffectCategory.manipulations
    public var enabled = true
    public var name = ""
    public var margin = CSPadding()
    /// 0 = AbsoluteSize, 1 = PercentageOfCanvas.
    public var marginMode = 0
    public var color = CSColor.transparent
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        var applied = margin
        if marginMode == 1 {
            applied = CSPadding(
                left: Int((Float(margin.left) / 100 * Float(image.width)).rounded()),
                top: Int((Float(margin.top) / 100 * Float(image.height)).rounded()),
                right: Int((Float(margin.right) / 100 * Float(image.width)).rounded()),
                bottom: Int((Float(margin.bottom) / 100 * Float(image.height)).rounded())
            )
        }
        return EffectDraw.addCanvas(image, margin: applied, color: color)
    }
}

public struct CropEffect: ImageEffecting {
    public static let typeName = "Crop"
    public static let category = EffectCategory.manipulations
    public var enabled = true
    public var name = ""
    public var margin = CSPadding()
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard margin.all != 0 else { return image }
        let rect = CGRect(x: margin.left, y: margin.top,
                          width: image.width - margin.horizontal,
                          height: image.height - margin.vertical)
        guard rect.width >= 1, rect.height >= 1 else { return image }
        return image.cropping(to: rect) ?? image
    }
}

public struct FlipEffect: ImageEffecting {
    public static let typeName = "Flip"
    public static let category = EffectCategory.manipulations
    public var enabled = true
    public var name = ""
    public var horizontally = false
    public var vertically = false
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard horizontally || vertically else { return image }
        return EffectDraw.render(width: image.width, height: image.height) { context in
            // context is top-left flipped; a raw draw is already a vertical mirror
            if horizontally {
                context.translateBy(x: CGFloat(image.width), y: 0)
                context.scaleBy(x: -1, y: 1)
            }
            let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            if vertically {
                context.draw(image, in: rect)
            } else {
                EffectDraw.draw(image, in: rect, context: context)
            }
        } ?? image
    }
}

public struct ForceProportionsEffect: ImageEffecting {
    public static let typeName = "ForceProportions"
    public static let category = EffectCategory.manipulations
    public var enabled = true
    public var name = ""
    public var proportionalWidth = 1
    public var proportionalHeight = 1
    /// 0 = Grow, 1 = Crop.
    public var method = 0
    public var growFillColor = CSColor.transparent
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard proportionalWidth > 0, proportionalHeight > 0 else { return image }
        let currentRatio = Float(image.width) / Float(image.height)
        let targetRatio = Float(proportionalWidth) / Float(proportionalHeight)
        let isTargetWider = targetRatio > currentRatio

        if method == 1 { // Crop
            var targetWidth = image.width, targetHeight = image.height
            var marginLeft = 0, marginTop = 0
            if isTargetWider {
                targetHeight = Int((Float(image.width) / targetRatio).rounded())
                marginTop = (image.height - targetHeight) / 2
            } else {
                targetWidth = Int((Float(image.height) * targetRatio).rounded())
                marginLeft = (image.width - targetWidth) / 2
            }
            return image.cropping(to: CGRect(x: marginLeft, y: marginTop,
                                             width: targetWidth, height: targetHeight)) ?? image
        }
        // Grow: enlarge the canvas, image centered
        var targetWidth = image.width, targetHeight = image.height
        if isTargetWider {
            targetWidth = Int((Float(image.height) * targetRatio).rounded())
        } else {
            targetHeight = Int((Float(image.width) / targetRatio).rounded())
        }
        return EffectDraw.render(width: targetWidth, height: targetHeight) { context in
            if growFillColor.a > 0 {
                context.setFillColor(growFillColor.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            }
            EffectDraw.draw(image, in: CGRect(x: (targetWidth - image.width) / 2,
                                              y: (targetHeight - image.height) / 2,
                                              width: image.width, height: image.height), context: context)
        } ?? image
    }
}

public struct ResizeEffect: ImageEffecting {
    public static let typeName = "Resize"
    public static let category = EffectCategory.manipulations
    public var enabled = true
    public var name = ""
    public var width = 250
    public var height = 0
    /// 0 = ResizeAll, 1 = ResizeIfBigger, 2 = ResizeIfSmaller.
    public var mode = 0
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard width > 0 || height > 0 else { return image }
        var w = width, h = height
        if w == 0 { w = Int(Float(image.width) * Float(h) / Float(image.height)) }
        if h == 0 { h = Int(Float(image.height) * Float(w) / Float(image.width)) }
        switch mode {
        case 1 where image.width <= w && image.height <= h: return image
        case 2 where image.width >= w && image.height >= h: return image
        default: break
        }
        return Self.scaled(image, width: w, height: h)
    }

    static func scaled(_ image: CGImage, width: Int, height: Int) -> CGImage {
        guard width > 0, height > 0 else { return image }
        return EffectDraw.render(width: width, height: height) { context in
            EffectDraw.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height), context: context)
        } ?? image
    }
}

public struct RotateEffect: ImageEffecting {
    public static let typeName = "Rotate"
    public static let category = EffectCategory.manipulations
    public var enabled = true
    public var name = ""
    public var angle: Float = 0
    public var upsize = true
    public var clip = false
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard angle != 0 else { return image }
        let radians = CGFloat(angle) * .pi / 180
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let boundsWidth = abs(w * cos(radians)) + abs(h * sin(radians))
        let boundsHeight = abs(w * sin(radians)) + abs(h * cos(radians))
        let (canvasWidth, canvasHeight) = upsize
            ? (Int(boundsWidth.rounded()), Int(boundsHeight.rounded()))
            : (image.width, image.height)
        // !upsize && !clip: scale the rotated bounds down to fit the original canvas
        let scale = (upsize || clip) ? 1 : min(w / boundsWidth, h / boundsHeight)

        return EffectDraw.render(width: canvasWidth, height: canvasHeight) { context in
            context.translateBy(x: CGFloat(canvasWidth) / 2, y: CGFloat(canvasHeight) / 2)
            context.rotate(by: radians)
            context.scaleBy(x: scale, y: scale)
            EffectDraw.draw(image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), context: context)
        } ?? image
    }
}

public struct RoundedCornersEffect: ImageEffecting {
    public static let typeName = "RoundedCorners"
    public static let category = EffectCategory.manipulations
    public var enabled = true
    public var name = ""
    public var cornerRadius = 20
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        let radius = min(CGFloat(cornerRadius), CGFloat(min(image.width, image.height)) / 2)
        guard radius > 0 else { return image }
        let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                          cornerWidth: radius, cornerHeight: radius, transform: nil)
        return EffectDraw.fillPath(path, with: image)
    }
}

public struct ScaleEffect: ImageEffecting {
    public static let typeName = "Scale"
    public static let category = EffectCategory.manipulations
    public var enabled = true
    public var name = ""
    public var widthPercentage: Float = 100
    public var heightPercentage: Float = 0
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard widthPercentage > 0 || heightPercentage > 0 else { return image }
        var wp = widthPercentage, hp = heightPercentage
        if wp == 0 { wp = hp }
        if hp == 0 { hp = wp }
        return ResizeEffect.scaled(image,
                                   width: Int(Float(image.width) * wp / 100),
                                   height: Int(Float(image.height) * hp / 100))
    }
}

public struct SkewEffect: ImageEffecting {
    public static let typeName = "Skew"
    public static let category = EffectCategory.manipulations
    public var enabled = true
    public var name = ""
    public var horizontally = 0
    public var vertically = 0
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        guard horizontally != 0 || vertically != 0 else { return image }
        return Self.skewed(image, x: horizontally, y: vertically)
    }

    /// ImageHelpers.AddSkew: shear onto a canvas grown by |x| and |y|.
    static func skewed(_ image: CGImage, x: Int, y: Int) -> CGImage {
        let width = image.width + abs(x)
        let height = image.height + abs(y)
        return EffectDraw.render(width: width, height: height) { context in
            let startX = CGFloat(-min(0, x)), startY = CGFloat(-min(0, y))
            let endX = CGFloat(max(0, x)), endY = CGFloat(max(0, y))
            // GDI DrawImage(points): top edge tilts by y, left edge tilts by x
            let shear = CGAffineTransform(
                a: 1, b: (endY - startY) / CGFloat(image.width),
                c: (endX - startX) / CGFloat(image.height), d: 1,
                tx: startX, ty: startY
            )
            context.concatenate(shear)
            EffectDraw.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height),
                            context: context)
        } ?? image
    }
}
