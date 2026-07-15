// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Image beautifier: the ShareX.MediaLib.ImageBeautifier pipeline
// (smart padding -> padding -> rounded corners -> margin -> shadow -> background).

import CoreGraphics
import Foundation

public struct ImageBeautifierOptions: Codable, Equatable, Sendable {
    public var margin = 80
    public var padding = 40
    public var smartPadding = true
    public var roundedCorner = 20
    public var shadowRadius = 30
    public var shadowOpacity = 80
    public var shadowDistance = 10
    public var shadowAngle = 180
    public var shadowColor = CSColor.black
    /// 0 Gradient, 1 Color, 2 Image, 3 Desktop (unsupported here), 4 Transparent.
    public var backgroundType = 0
    public var backgroundGradient = GradientInfo(type: .forwardDiagonal, colors: [
        GradientStop(color: CSColor(r: 255, g: 81, b: 47), location: 0),
        GradientStop(color: CSColor(r: 221, g: 36, b: 118), location: 100)
    ])
    public var backgroundColor = CSColor(r: 34, g: 34, b: 34)
    public var backgroundImageFilePath = ""

    public init() {}
}

public enum ImageBeautifier {
    public static func render(_ image: CGImage, options: ImageBeautifierOptions) -> CGImage {
        var result = image

        // padding color and smart padding come from the uniform border, like LoadImage
        var paddingColor = CSColor.transparent
        if let buffer = PixelBuffer(image: image), buffer.pixels.count >= 4 {
            paddingColor = CSColor(r: buffer.pixels[0], g: buffer.pixels[1],
                                   b: buffer.pixels[2], a: buffer.pixels[3])
        }
        if options.smartPadding {
            result = AutoCropEffect().apply(result)
        }

        if options.padding > 0 {
            let pad = options.padding
            result = EffectDraw.addCanvas(result, margin: CSPadding(left: pad, top: pad, right: pad, bottom: pad),
                                          color: paddingColor)
        }
        if options.roundedCorner > 0 {
            var rounded = RoundedCornersEffect()
            rounded.cornerRadius = options.roundedCorner
            result = rounded.apply(result)
        }
        if options.margin > 0 {
            let margin = options.margin
            result = EffectDraw.addCanvas(result, margin: CSPadding(left: margin, top: margin,
                                                                    right: margin, bottom: margin))
        }
        if options.shadowOpacity > 0, options.shadowRadius > 0 || options.shadowDistance > 0 {
            // MathHelpers.DegreeToVector2(angle - 90, distance)
            let radians = Double(options.shadowAngle - 90) * .pi / 180
            var shadow = ShadowEffect()
            shadow.opacity = Float(options.shadowOpacity) / 100
            shadow.size = options.shadowRadius
            shadow.color = options.shadowColor
            shadow.offset = CSPoint(x: Int((cos(radians) * Double(options.shadowDistance)).rounded()),
                                    y: Int((sin(radians) * Double(options.shadowDistance)).rounded()))
            shadow.autoResize = false
            result = shadow.apply(result)
        }

        switch options.backgroundType {
        case 0 where options.backgroundGradient.isValid:
            var background = DrawBackgroundEffect()
            background.useGradient = true
            background.gradient = options.backgroundGradient
            result = background.apply(result)
        case 1 where options.backgroundColor.a > 0:
            var background = DrawBackgroundEffect()
            background.color = options.backgroundColor
            result = background.apply(result)
        case 2, 3:
            // ponytail: Desktop mode reuses the image path field; wallpaper lookup if anyone asks
            var background = DrawBackgroundImageEffect()
            background.imageFilePath = options.backgroundImageFilePath
            background.center = false
            result = background.apply(result)
        default:
            break
        }
        return result
    }
}
