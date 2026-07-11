// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Adjustment effects: GDI+ ColorMatrix ports with the exact matrices from
// ShareX.HelpersLib.ColorMatrixManager (grayscale weights 0.212671/0.715160/0.072169).

import CoreGraphics
import Foundation

private let rw: Float = 0.212671
private let gw: Float = 0.715160
private let bw: Float = 0.072169

public struct AlphaEffect: ImageEffecting {
    public static let typeName = "Alpha"
    public static let category = EffectCategory.adjustments
    public var enabled = true
    public var name = ""
    public var value: Float = 1
    public var addition: Float = 0
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.colorMatrix(image, [
            [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0],
            [0, 0, 0, value], [0, 0, 0, addition]
        ])
    }
}

public struct BlackWhiteEffect: ImageEffecting {
    public static let typeName = "BlackWhite"
    public static let category = EffectCategory.adjustments
    public var enabled = true
    public var name = ""
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.colorMatrix(image, [
            [1.5, 1.5, 1.5, 0], [1.5, 1.5, 1.5, 0], [1.5, 1.5, 1.5, 0],
            [0, 0, 0, 1], [-1, -1, -1, 0]
        ])
    }
}

public struct BrightnessEffect: ImageEffecting {
    public static let typeName = "Brightness"
    public static let category = EffectCategory.adjustments
    public var enabled = true
    public var name = ""
    public var value: Float = 0
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.colorMatrix(image, [
            [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0],
            [0, 0, 0, 1], [value, value, value, 0]
        ])
    }
}

public struct ColorizeEffect: ImageEffecting {
    public static let typeName = "Colorize"
    public static let category = EffectCategory.adjustments
    public var enabled = true
    public var name = ""
    public var color = CSColor.red
    public var value: Float = 0
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        let r = Float(color.r) / 255, g = Float(color.g) / 255, b = Float(color.b) / 255
        let inv = 1 - value
        return PixelOps.colorMatrix(image, [
            [inv + value * r * rw, value * g * rw, value * b * rw, 0],
            [value * r * gw, inv + value * g * gw, value * b * gw, 0],
            [value * r * bw, value * g * bw, inv + value * b * bw, 0],
            [0, 0, 0, 1], [0, 0, 0, 0]
        ])
    }
}

public struct ContrastEffect: ImageEffecting {
    public static let typeName = "Contrast"
    public static let category = EffectCategory.adjustments
    public var enabled = true
    public var name = ""
    public var value: Float = 1
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.colorMatrix(image, [
            [value, 0, 0, 0], [0, value, 0, 0], [0, 0, value, 0],
            [0, 0, 0, 1], [0, 0, 0, 0]
        ])
    }
}

public struct GammaEffect: ImageEffecting {
    public static let typeName = "Gamma"
    public static let category = EffectCategory.adjustments
    public var enabled = true
    public var name = ""
    public var value: Float = 1
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.gamma(image, value)
    }
}

public struct GrayscaleEffect: ImageEffecting {
    public static let typeName = "Grayscale"
    public static let category = EffectCategory.adjustments
    public var enabled = true
    public var name = ""
    public var value: Float = 1
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.colorMatrix(image, [
            [rw * value, rw * value, rw * value, 0],
            [gw * value, gw * value, gw * value, 0],
            [bw * value, bw * value, bw * value, 0],
            [0, 0, 0, 1], [0, 0, 0, 0]
        ])
    }
}

public struct HueEffect: ImageEffecting {
    public static let typeName = "Hue"
    public static let category = EffectCategory.adjustments
    public var enabled = true
    public var name = ""
    public var angle: Float = 0
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        let a = angle * .pi / 180
        let c = cos(a), s = sin(a)
        return PixelOps.colorMatrix(image, [
            [rw + c * (1 - rw) + s * -rw, rw + c * -rw + s * 0.143, rw + c * -rw + s * -(1 - rw), 0],
            [gw + c * -gw + s * -gw, gw + c * (1 - gw) + s * 0.14, gw + c * -gw + s * gw, 0],
            [bw + c * -bw + s * (1 - bw), bw + c * -bw + s * -0.283, bw + c * (1 - bw) + s * bw, 0],
            [0, 0, 0, 1], [0, 0, 0, 0]
        ])
    }
}

public struct InverseEffect: ImageEffecting {
    public static let typeName = "Inverse"
    public static let category = EffectCategory.adjustments
    public var enabled = true
    public var name = ""
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.colorMatrix(image, [
            [-1, 0, 0, 0], [0, -1, 0, 0], [0, 0, -1, 0],
            [0, 0, 0, 1], [1, 1, 1, 0]
        ])
    }
}

public struct MatrixColorEffect: ImageEffecting {
    public static let typeName = "MatrixColor"
    public static let category = EffectCategory.adjustments
    public var enabled = true
    public var name = ""
    // out_red = r*rr + g*rg + b*rb + a*ra + ro, etc.
    public var rr: Float = 1, rg: Float = 0, rb: Float = 0, ra: Float = 0, ro: Float = 0
    public var gr: Float = 0, gg: Float = 1, gb: Float = 0, ga: Float = 0, go: Float = 0
    public var br: Float = 0, bg: Float = 0, bb: Float = 1, ba: Float = 0, bo: Float = 0
    public var ar: Float = 0, ag: Float = 0, ab: Float = 0, aa: Float = 1, ao: Float = 0
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.colorMatrix(image, [
            [rr, gr, br, ar],
            [rg, gg, bg, ag],
            [rb, gb, bb, ab],
            [ra, ga, ba, aa],
            [ro, go, bo, ao]
        ])
    }
}

public struct PolaroidEffect: ImageEffecting {
    public static let typeName = "Polaroid"
    public static let category = EffectCategory.adjustments
    public var enabled = true
    public var name = ""
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.colorMatrix(image, [
            [1.438, -0.062, -0.062, 0],
            [-0.122, 1.378, -0.122, 0],
            [-0.016, -0.016, 1.483, 0],
            [0, 0, 0, 1],
            [-0.03, 0.05, -0.02, 0]
        ])
    }
}

public struct ReplaceColorEffect: ImageEffecting {
    public static let typeName = "ReplaceColor"
    public static let category = EffectCategory.adjustments
    public var enabled = true
    public var name = ""
    public var sourceColor = CSColor.white
    public var autoSourceColor = false
    public var targetColor = CSColor.transparent
    public var threshold = 0
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.replaceColor(image, source: sourceColor, target: targetColor,
                              autoSource: autoSourceColor, threshold: threshold)
    }
}

public struct SaturationEffect: ImageEffecting {
    public static let typeName = "Saturation"
    public static let category = EffectCategory.adjustments
    public var enabled = true
    public var name = ""
    public var value: Float = 1
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        let inv = 1 - value
        return PixelOps.colorMatrix(image, [
            [inv * rw + value, inv * rw, inv * rw, 0],
            [inv * gw, inv * gw + value, inv * gw, 0],
            [inv * bw, inv * bw, inv * bw + value, 0],
            [0, 0, 0, 1], [0, 0, 0, 0]
        ])
    }
}

public struct SelectiveColorEffect: ImageEffecting {
    public static let typeName = "SelectiveColor"
    public static let category = EffectCategory.adjustments
    public var enabled = true
    public var name = ""
    public var lightColor = CSColor.white
    public var darkColor = CSColor.black
    public var paletteSize = 10
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.selectiveColor(image, light: lightColor, dark: darkColor, paletteSize: paletteSize)
    }
}

public struct SepiaEffect: ImageEffecting {
    public static let typeName = "Sepia"
    public static let category = EffectCategory.adjustments
    public var enabled = true
    public var name = ""
    public var value: Float = 1
    public init() {}

    public func apply(_ image: CGImage) -> CGImage {
        PixelOps.colorMatrix(image, [
            [0.393 * value, 0.349 * value, 0.272 * value, 0],
            [0.769 * value, 0.686 * value, 0.534 * value, 0],
            [0.189 * value, 0.168 * value, 0.131 * value, 0],
            [0, 0, 0, 1], [0, 0, 0, 0]
        ])
    }
}
