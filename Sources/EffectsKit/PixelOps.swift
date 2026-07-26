// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// CPU pixel operations mirroring the GDI+ semantics of the C# effects:
// straight (unpremultiplied) RGBA like 32bppArgb, edge-clamped convolution,
// GDI+ 5x5 color matrices applied as [r g b a 1] * M.

import CoreGraphics
import Foundation

/// Straight-alpha RGBA8 pixel buffer.
struct PixelBuffer {
    var pixels: [UInt8]
    let width: Int
    let height: Int

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        self.width = width
        self.height = height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard ok else { return nil }
        // unpremultiply to straight alpha
        for i in stride(from: 0, to: data.count, by: 4) {
            let a = data[i + 3]
            if a != 0 && a != 255 {
                let alpha = Int(a)
                data[i] = UInt8(min(255, Int(data[i]) * 255 / alpha))
                data[i + 1] = UInt8(min(255, Int(data[i + 1]) * 255 / alpha))
                data[i + 2] = UInt8(min(255, Int(data[i + 2]) * 255 / alpha))
            }
        }
        pixels = data
    }

    func makeImage() -> CGImage? {
        var data = pixels
        for i in stride(from: 0, to: data.count, by: 4) {
            let a = Int(data[i + 3])
            if a != 255 {
                data[i] = UInt8(Int(data[i]) * a / 255)
                data[i + 1] = UInt8(Int(data[i + 1]) * a / 255)
                data[i + 2] = UInt8(Int(data[i + 2]) * a / 255)
            }
        }
        return data.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }
    }

    @inline(__always)
    func index(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }
}

enum PixelOps {
    /// Runs a straight-alpha buffer transform over a CGImage.
    static func transform(_ image: CGImage, _ body: (inout PixelBuffer) -> Void) -> CGImage {
        guard var buffer = PixelBuffer(image: image) else { return image }
        body(&buffer)
        return buffer.makeImage() ?? image
    }

    // MARK: Color matrix

    /// GDI+ 5x5 matrix, row-major: out_c = Σ in_r * m[r][c] + m[4][c], channels 0-1 scaled.
    static func colorMatrix(_ m: [[Float]], _ buffer: inout PixelBuffer) {
        for i in stride(from: 0, to: buffer.pixels.count, by: 4) {
            let r = Float(buffer.pixels[i]) / 255
            let g = Float(buffer.pixels[i + 1]) / 255
            let b = Float(buffer.pixels[i + 2]) / 255
            let a = Float(buffer.pixels[i + 3]) / 255
            for c in 0..<4 {
                let value = r * m[0][c] + g * m[1][c] + b * m[2][c] + a * m[3][c] + m[4][c]
                buffer.pixels[i + c] = UInt8(max(0, min(255, value * 255)))
            }
        }
    }

    static func colorMatrix(_ image: CGImage, _ m: [[Float]]) -> CGImage {
        transform(image) { colorMatrix(m, &$0) }
    }

    /// GDI+ ImageAttributes.SetGamma: out = in^(1/gamma) on RGB.
    static func gamma(_ image: CGImage, _ value: Float) -> CGImage {
        let gamma = max(0.1, min(5.0, value))
        var lut = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 {
            lut[i] = UInt8(max(0, min(255, pow(Float(i) / 255, 1 / gamma) * 255 + 0.5)))
        }
        return transform(image) { buffer in
            for i in stride(from: 0, to: buffer.pixels.count, by: 4) {
                buffer.pixels[i] = lut[Int(buffer.pixels[i])]
                buffer.pixels[i + 1] = lut[Int(buffer.pixels[i + 1])]
                buffer.pixels[i + 2] = lut[Int(buffer.pixels[i + 2])]
            }
        }
    }

    // MARK: Convolution

    /// Edge-clamped convolution matching ConvolutionMatrixManager.Apply.
    /// Alpha passes through from the source unless considerAlpha.
    static func convolve(_ image: CGImage, kernel: [[Double]], offset: Double = 0,
                         considerAlpha: Bool = false) -> CGImage {
        guard let source = PixelBuffer(image: image) else { return image }
        var dest = source
        let kh = kernel.count, kw = kernel[0].count
        let originX = (kw - 1) / 2, originY = (kh - 1) / 2
        for y in 0..<source.height {
            for x in 0..<source.width {
                var r = 0.0, g = 0.0, b = 0.0, a = 0.0
                for fy in 0..<kh {
                    let sy = min(max(y + fy - originY, 0), source.height - 1)
                    for fx in 0..<kw {
                        let sx = min(max(x + fx - originX, 0), source.width - 1)
                        let k = kernel[fy][fx]
                        let i = source.index(sx, sy)
                        r += k * Double(source.pixels[i])
                        g += k * Double(source.pixels[i + 1])
                        b += k * Double(source.pixels[i + 2])
                        if considerAlpha { a += k * Double(source.pixels[i + 3]) }
                    }
                }
                let di = dest.index(x, y)
                dest.pixels[di] = UInt8(max(0, min(255, r + offset)))
                dest.pixels[di + 1] = UInt8(max(0, min(255, g + offset)))
                dest.pixels[di + 2] = UInt8(max(0, min(255, b + offset)))
                if considerAlpha {
                    dest.pixels[di + 3] = UInt8(max(0, min(255, a + offset)))
                }
            }
        }
        return dest.makeImage() ?? image
    }

    /// 1D gaussian kernel, normalized (ConvolutionMatrixManager.GaussianBlur).
    static func gaussianKernel(size: Int, sigma: Double) -> [Double] {
        let mid = Double(size - 1) / 2
        var kernel = (0..<size).map { i -> Double in
            let x = Double(i) - mid
            return exp(-x * x / (2 * sigma * sigma)) / (sqrt(2 * .pi) * sigma)
        }
        let sum = kernel.reduce(0, +)
        for i in kernel.indices { kernel[i] /= sum }
        return kernel
    }

    // MARK: Box blur (C# ImageHelpers.BoxBlur: 4 alternating passes, all channels)

    static func boxBlur(_ image: CGImage, range: Int) -> CGImage {
        guard range > 1 else { return image }
        var range = range
        if range % 2 == 0 { range += 1 }
        return transform(image) { buffer in
            boxBlurPass(&buffer, range: range, horizontal: true)
            boxBlurPass(&buffer, range: range, horizontal: false)
            boxBlurPass(&buffer, range: range, horizontal: true)
            boxBlurPass(&buffer, range: range, horizontal: false)
        }
    }

    private static func boxBlurPass(_ buffer: inout PixelBuffer, range: Int, horizontal: Bool) {
        let half = range / 2
        let (outer, inner) = horizontal ? (buffer.height, buffer.width) : (buffer.width, buffer.height)
        var line = [UInt8](repeating: 0, count: inner * 4)
        for o in 0..<outer {
            var sum = (r: 0, g: 0, b: 0, a: 0)
            var count = 0
            @inline(__always) func srcIndex(_ i: Int) -> Int {
                horizontal ? buffer.index(i, o) : buffer.index(o, i)
            }
            // sliding accumulator; window clamped at line edges
            for i in -half...half where i >= 0 && i < inner {
                let s = srcIndex(i)
                sum.r += Int(buffer.pixels[s]); sum.g += Int(buffer.pixels[s + 1])
                sum.b += Int(buffer.pixels[s + 2]); sum.a += Int(buffer.pixels[s + 3])
                count += 1
            }
            for i in 0..<inner {
                line[i * 4] = UInt8(sum.r / count)
                line[i * 4 + 1] = UInt8(sum.g / count)
                line[i * 4 + 2] = UInt8(sum.b / count)
                line[i * 4 + 3] = UInt8(sum.a / count)
                let leaving = i - half, entering = i + half + 1
                if leaving >= 0 {
                    let s = srcIndex(leaving)
                    sum.r -= Int(buffer.pixels[s]); sum.g -= Int(buffer.pixels[s + 1])
                    sum.b -= Int(buffer.pixels[s + 2]); sum.a -= Int(buffer.pixels[s + 3])
                    count -= 1
                }
                if entering < inner {
                    let s = srcIndex(entering)
                    sum.r += Int(buffer.pixels[s]); sum.g += Int(buffer.pixels[s + 1])
                    sum.b += Int(buffer.pixels[s + 2]); sum.a += Int(buffer.pixels[s + 3])
                    count += 1
                }
            }
            for i in 0..<inner {
                let d = srcIndex(i)
                buffer.pixels[d] = line[i * 4]
                buffer.pixels[d + 1] = line[i * 4 + 1]
                buffer.pixels[d + 2] = line[i * 4 + 2]
                buffer.pixels[d + 3] = line[i * 4 + 3]
            }
        }
    }

    // MARK: Misc buffer ops

    /// ImageHelpers.Pixelate: alpha-weighted block average.
    static func pixelate(_ image: CGImage, size: Int) -> CGImage {
        guard size > 1 else { return image }
        return transform(image) { buffer in
            for by in stride(from: 0, to: buffer.height, by: size) {
                for bx in stride(from: 0, to: buffer.width, by: size) {
                    let xLimit = min(bx + size, buffer.width)
                    let yLimit = min(by + size, buffer.height)
                    var r = 0.0, g = 0.0, b = 0.0, a = 0.0, weighted = 0.0
                    let count = Double((xLimit - bx) * (yLimit - by))
                    for y in by..<yLimit {
                        for x in bx..<xLimit {
                            let i = buffer.index(x, y)
                            let weight = Double(buffer.pixels[i + 3]) / 255
                            r += Double(buffer.pixels[i]) * weight
                            g += Double(buffer.pixels[i + 1]) * weight
                            b += Double(buffer.pixels[i + 2]) * weight
                            a += Double(buffer.pixels[i + 3]) * weight
                            weighted += weight
                        }
                    }
                    let avg: (UInt8, UInt8, UInt8, UInt8) = weighted > 0
                        ? (UInt8(min(255, r / weighted)), UInt8(min(255, g / weighted)),
                           UInt8(min(255, b / weighted)), UInt8(min(255, a / count)))
                        : (0, 0, 0, 0)
                    for y in by..<yLimit {
                        for x in bx..<xLimit {
                            let i = buffer.index(x, y)
                            (buffer.pixels[i], buffer.pixels[i + 1],
                             buffer.pixels[i + 2], buffer.pixels[i + 3]) = avg
                        }
                    }
                }
            }
        }
    }

    /// ImageHelpers.ColorDepth: quantize channels to 2^bits levels.
    static func colorDepth(_ image: CGImage, bitsPerChannel: Int) -> CGImage {
        guard (1...8).contains(bitsPerChannel), bitsPerChannel < 8 else { return image }
        let interval = 255.0 / (pow(2, Double(bitsPerChannel)) - 1)
        var lut = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 {
            lut[i] = UInt8(max(0, min(255, ((Double(i) / interval).rounded() * interval).rounded())))
        }
        return transform(image) { buffer in
            for i in stride(from: 0, to: buffer.pixels.count, by: 4) {
                buffer.pixels[i] = lut[Int(buffer.pixels[i])]
                buffer.pixels[i + 1] = lut[Int(buffer.pixels[i + 1])]
                buffer.pixels[i + 2] = lut[Int(buffer.pixels[i + 2])]
            }
        }
    }

    /// ImageHelpers.ReplaceColor.
    static func replaceColor(_ image: CGImage, source: CSColor, target: CSColor,
                             autoSource: Bool, threshold: Int) -> CGImage {
        transform(image) { buffer in
            var src = source
            if autoSource, buffer.pixels.count >= 4 {
                src = CSColor(r: buffer.pixels[0], g: buffer.pixels[1],
                              b: buffer.pixels[2], a: buffer.pixels[3])
            }
            for i in stride(from: 0, to: buffer.pixels.count, by: 4) {
                let close: Bool
                if threshold == 0 {
                    close = buffer.pixels[i] == src.r && buffer.pixels[i + 1] == src.g
                        && buffer.pixels[i + 2] == src.b && buffer.pixels[i + 3] == src.a
                } else {
                    close = abs(Int(buffer.pixels[i]) - Int(src.r)) <= threshold
                        && abs(Int(buffer.pixels[i + 1]) - Int(src.g)) <= threshold
                        && abs(Int(buffer.pixels[i + 2]) - Int(src.b)) <= threshold
                }
                if close {
                    buffer.pixels[i] = target.r
                    buffer.pixels[i + 1] = target.g
                    buffer.pixels[i + 2] = target.b
                    buffer.pixels[i + 3] = target.a
                }
            }
        }
    }

    /// ShareX ColorHelpers.PerceivedBrightness.
    @inline(__always)
    static func perceivedBrightness(_ r: Double, _ g: Double, _ b: Double) -> Int {
        Int(sqrt(r * r * 0.241 + g * g * 0.691 + b * b * 0.068))
    }

    /// ImageHelpers.SelectiveColor: map pixels to a light->dark palette by brightness.
    static func selectiveColor(_ image: CGImage, light: CSColor, dark: CSColor, paletteSize: Int) -> CGImage {
        let count = max(paletteSize, 2)
        var palette: [(brightness: Int, color: CSColor)] = []
        for i in 0..<count {
            let t = Double(i) / Double(count - 1)
            let color = CSColor(
                r: UInt8(Double(light.r) + (Double(dark.r) - Double(light.r)) * t),
                g: UInt8(Double(light.g) + (Double(dark.g) - Double(light.g)) * t),
                b: UInt8(Double(light.b) + (Double(dark.b) - Double(light.b)) * t),
                a: UInt8(Double(light.a) + (Double(dark.a) - Double(light.a)) * t)
            )
            palette.append((perceivedBrightness(Double(color.r), Double(color.g), Double(color.b)), color))
        }
        return transform(image) { buffer in
            for i in stride(from: 0, to: buffer.pixels.count, by: 4) {
                let brightness = perceivedBrightness(Double(buffer.pixels[i]),
                                                     Double(buffer.pixels[i + 1]),
                                                     Double(buffer.pixels[i + 2]))
                let closest = palette.min { abs($0.brightness - brightness) < abs($1.brightness - brightness) }!
                buffer.pixels[i] = closest.color.r
                buffer.pixels[i + 1] = closest.color.g
                buffer.pixels[i + 2] = closest.color.b
            }
        }
    }

    /// RGBSplit: channels sampled at offsets, premultiplied by their alpha; alpha = average.
    static func rgbSplit(_ image: CGImage, red: CSPoint, green: CSPoint, blue: CSPoint) -> CGImage {
        guard let source = PixelBuffer(image: image) else { return image }
        var dest = source
        let right = source.width - 1, bottom = source.height - 1
        for y in 0..<source.height {
            for x in 0..<source.width {
                let ri = source.index(min(max(x - red.x, 0), right), min(max(y - red.y, 0), bottom))
                let gi = source.index(min(max(x - green.x, 0), right), min(max(y - green.y, 0), bottom))
                let bi = source.index(min(max(x - blue.x, 0), right), min(max(y - blue.y, 0), bottom))
                let di = dest.index(x, y)
                dest.pixels[di] = UInt8(Int(source.pixels[ri]) * Int(source.pixels[ri + 3]) / 255)
                dest.pixels[di + 1] = UInt8(Int(source.pixels[gi + 1]) * Int(source.pixels[gi + 3]) / 255)
                dest.pixels[di + 2] = UInt8(Int(source.pixels[bi + 2]) * Int(source.pixels[bi + 3]) / 255)
                dest.pixels[di + 3] = UInt8((Int(source.pixels[ri + 3]) + Int(source.pixels[gi + 3]) + Int(source.pixels[bi + 3])) / 3)
            }
        }
        return dest.makeImage() ?? image
    }

    /// ImageHelpers.MakeOutline: nearest distance to an opaque pixel shapes an outline band.
    static func outline(_ image: CGImage, minRadius: Int, maxRadius: Int, color: CSColor) -> CGImage? {
        guard let source = PixelBuffer(image: image) else { return nil }
        var dest = PixelBuffer(image: image)!
        for i in stride(from: 0, to: dest.pixels.count, by: 4) {
            dest.pixels[i + 3] = 0
        }
        let radius = maxRadius
        for y in 0..<source.height {
            for x in 0..<source.width {
                // nearest fully-opaque pixel within radius
                var dist2 = radius * radius + 1
                for ty in max(y - radius, 0)...min(y + radius, source.height - 1) {
                    for tx in max(x - radius, 0)...min(x + radius, source.width - 1) {
                        if source.pixels[source.index(tx, ty) + 3] >= 255 {
                            let dx = tx - x, dy = ty - y
                            dist2 = min(dist2, dx * dx + dy * dy)
                        }
                    }
                }
                let dist = Float(dist2).squareRoot()
                if dist > Float(minRadius), dist < Float(maxRadius) {
                    var alpha: Float = 255
                    if dist - Float(minRadius) < 1 {
                        alpha = 255 * (dist - Float(minRadius))
                    } else if Float(maxRadius) - dist < 1 {
                        alpha = 255 * (Float(maxRadius) - dist)
                    }
                    let i = dest.index(x, y)
                    dest.pixels[i] = color.r
                    dest.pixels[i + 1] = color.g
                    dest.pixels[i + 2] = color.b
                    dest.pixels[i + 3] = UInt8(max(0, min(255, alpha)))
                }
            }
        }
        return dest.makeImage()
    }

    /// ImageHelpers.AddReflection alpha ramp: cap alpha from maxAlpha at top to minAlpha at bottom.
    static func reflectionAlphaRamp(_ image: CGImage, maxAlpha: Int, minAlpha: Int) -> CGImage {
        transform(image) { buffer in
            let alphaAdd = Double(maxAlpha - minAlpha)
            let span = Double(max(buffer.height - 1, 1))
            for y in 0..<buffer.height {
                let cap = UInt8(max(0, min(255, Double(maxAlpha) - alphaAdd * Double(y) / span)))
                for x in 0..<buffer.width {
                    let i = buffer.index(x, y)
                    if buffer.pixels[i + 3] > cap {
                        buffer.pixels[i + 3] = cap
                    }
                }
            }
        }
    }

    /// ColorMatrixManager.Mask: silhouette of the image alpha in a flat color * opacity.
    static func mask(_ image: CGImage, opacity: Float, color: CSColor) -> CGImage {
        colorMatrix(image, [
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, Float(color.a) / 255 * opacity],
            [Float(color.r) / 255, Float(color.g) / 255, Float(color.b) / 255, 0]
        ])
    }
}
