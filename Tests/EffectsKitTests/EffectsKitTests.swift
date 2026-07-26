// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import CoreGraphics
import Foundation
import Testing
@testable import EffectsKit

private func makeImage(width: Int = 8, height: Int = 8,
                       color: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) = (1, 0, 0, 1)) -> CGImage {
    let context = CGContext(
        data: nil, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}

private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    let buffer = PixelBuffer(image: image)!
    let i = buffer.index(x, y)
    return (buffer.pixels[i], buffer.pixels[i + 1], buffer.pixels[i + 2], buffer.pixels[i + 3])
}

struct RegistryTests {
    @Test func allFiftyOneEffectsRegistered() {
        #expect(EffectRegistry.allTypes.count == 51)
        #expect(EffectRegistry.types(in: .adjustments).count == 15)
        #expect(EffectRegistry.types(in: .filters).count == 18)
        #expect(EffectRegistry.types(in: .manipulations).count == 10)
        #expect(EffectRegistry.types(in: .drawings).count == 8)
    }

    @Test func typeNamesAreUnique() {
        let names = EffectRegistry.allTypes.map { $0.typeName }
        #expect(Set(names).count == names.count)
    }
}

struct SerializationTests {
    @Test func presetRoundTripsThroughConfigJSON() throws {
        var resize = ResizeEffect()
        resize.width = 640
        resize.height = 360
        var text = DrawTextEffect()
        text.text = "hello %y"
        text.textColor = CSColor(r: 1, g: 2, b: 3)
        let preset = ImageEffectPreset(name: "Test", effects: [resize, text])

        let data = try preset.configJSON()
        let restored = try ImageEffectPreset.fromConfigJSON(data)
        #expect(restored.name == "Test")
        #expect(restored.effects.count == 2)
        let restoredResize = try #require(restored.effects[0] as? ResizeEffect)
        #expect(restoredResize.width == 640)
        let restoredText = try #require(restored.effects[1] as? DrawTextEffect)
        #expect(restoredText.text == "hello %y")
        #expect(restoredText.textColor == CSColor(r: 1, g: 2, b: 3))
    }

    @Test func decodeFillsMissingKeysWithDefaults() throws {
        // C# DefaultValueHandling.Ignore omits default-valued properties
        let json = """
        {"Name": "Partial", "Effects": [{"$type": "Shadow", "Size": 25}]}
        """
        let preset = try ImageEffectPreset.fromConfigJSON(Data(json.utf8))
        let shadow = try #require(preset.effects.first as? ShadowEffect)
        #expect(shadow.size == 25)
        #expect(shadow.opacity == 0.6)       // default preserved
        #expect(shadow.autoResize == true)   // default preserved
    }

    @Test func unknownEffectTypesAreSkippedNotFatal() throws {
        let json = """
        {"Name": "X", "Effects": [{"$type": "SomeWindowsOnlyThing"}, {"$type": "Grayscale"}]}
        """
        let preset = try ImageEffectPreset.fromConfigJSON(Data(json.utf8))
        #expect(preset.effects.count == 1)
        #expect(preset.effects.first is GrayscaleEffect)
    }

    @Test func csharpScalarStringsParse() throws {
        #expect(CSColor(string: "235, 235, 235") == CSColor(r: 235, g: 235, b: 235))
        #expect(CSColor(string: "125, 0, 0, 0") == CSColor(r: 0, g: 0, b: 0, a: 125))
        #expect(CSColor(string: "Transparent").a == 0)
        #expect(CSColor(string: "Red") == CSColor(r: 255, g: 0, b: 0))

        let font = try EffectJSON.decoder.decode(CSFont.self, from: Data("\"Arial, 11.25pt, style=Bold\"".utf8))
        #expect(font.family == "Arial")
        #expect(font.size == 11.25)
        #expect(font.bold)

        let padding = try EffectJSON.decoder.decode(CSPadding.self, from: Data("\"1, 2, 3, 4\"".utf8))
        #expect(padding.left == 1 && padding.top == 2 && padding.right == 3 && padding.bottom == 4)
    }

    @Test func sxieRoundTrip() throws {
        var preset = ImageEffectPreset.defaultPreset()
        preset.name = "SXIE Test"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).sxie")
        defer { try? FileManager.default.removeItem(at: url) }
        try preset.exportSXIE(to: url)
        let restored = try ImageEffectPreset.importSXIE(from: url)
        #expect(restored.name == "SXIE Test")
        #expect(restored.effects.count == 2)
        #expect(restored.effects[0] is CanvasEffect)
        #expect(restored.effects[1] is DrawTextEffect)
    }
}

struct AdjustmentTests {
    @Test func grayscaleUsesRec709Weights() {
        let out = GrayscaleEffect().apply(makeImage(color: (1, 0, 0, 1)))
        let p = pixel(out, 4, 4)
        // pure red -> 0.212671 * 255 ≈ 54 on every channel
        #expect(abs(Int(p.r) - 54) <= 1)
        #expect(p.r == p.g && p.g == p.b)
        #expect(p.a == 255)
    }

    @Test func inverseInvertsChannels() {
        let out = InverseEffect().apply(makeImage(color: (1, 0, 0, 1)))
        let p = pixel(out, 4, 4)
        #expect(p.r == 0 && p.g == 255 && p.b == 255 && p.a == 255)
    }

    @Test func brightnessAddsToChannels() {
        var effect = BrightnessEffect()
        effect.value = 0.5
        let out = effect.apply(makeImage(color: (0, 0, 0, 1)))
        let p = pixel(out, 4, 4)
        #expect(abs(Int(p.r) - 127) <= 1)
    }

    @Test func alphaEffectScalesAlpha() {
        var effect = AlphaEffect()
        effect.value = 0.5
        let out = effect.apply(makeImage(color: (1, 1, 1, 1)))
        #expect(abs(Int(pixel(out, 4, 4).a) - 127) <= 1)
    }

    @Test func replaceColorSwapsExactMatches() {
        var effect = ReplaceColorEffect()
        effect.sourceColor = CSColor(r: 255, g: 0, b: 0)
        effect.targetColor = CSColor(r: 0, g: 255, b: 0)
        let out = effect.apply(makeImage(color: (1, 0, 0, 1)))
        let p = pixel(out, 4, 4)
        #expect(p.r == 0 && p.g == 255)
    }
}

struct GeometryTests {
    @Test func canvasGrowsBottomMargin() {
        var effect = CanvasEffect()
        effect.margin = CSPadding(left: 0, top: 0, right: 0, bottom: 30)
        let out = effect.apply(makeImage(width: 10, height: 10))
        #expect(out.width == 10 && out.height == 40)
        #expect(pixel(out, 5, 25).a == 0) // new area transparent
        #expect(pixel(out, 5, 5).a == 255)
    }

    @Test func cropRemovesMargins() {
        var effect = CropEffect()
        effect.margin = CSPadding(left: 2, top: 1, right: 3, bottom: 2)
        let out = effect.apply(makeImage(width: 10, height: 10))
        #expect(out.width == 5 && out.height == 7)
    }

    @Test func resizeKeepsAspectWhenHeightZero() {
        var effect = ResizeEffect()
        effect.width = 4
        effect.height = 0
        let out = effect.apply(makeImage(width: 8, height: 4))
        #expect(out.width == 4 && out.height == 2)
    }

    @Test func resizeIfBiggerSkipsSmallImages() {
        var effect = ResizeEffect()
        effect.width = 100
        effect.height = 100
        effect.mode = 1
        let out = effect.apply(makeImage(width: 8, height: 8))
        #expect(out.width == 8)
    }

    @Test func roundedCornersClearCornerPixels() {
        var effect = RoundedCornersEffect()
        effect.cornerRadius = 8
        let out = effect.apply(makeImage(width: 32, height: 32))
        #expect(pixel(out, 0, 0).a == 0)
        #expect(pixel(out, 16, 16).a == 255)
    }

    @Test func rotateUpsizeGrowsCanvas() {
        var effect = RotateEffect()
        effect.angle = 45
        let out = effect.apply(makeImage(width: 10, height: 10))
        #expect(out.width > 10 && out.height > 10)
    }

    @Test func forceProportionsCropsToTargetRatio() {
        var effect = ForceProportionsEffect()
        effect.proportionalWidth = 1
        effect.proportionalHeight = 1
        effect.method = 1
        let out = effect.apply(makeImage(width: 20, height: 10))
        #expect(out.width == 10 && out.height == 10)
    }

    @Test func autoCropTrimsUniformBorder() {
        // 10x10 transparent with an opaque 4x4 block at (3,3)
        let base = EffectDraw.render(width: 10, height: 10) { context in
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(x: 3, y: 3, width: 4, height: 4))
        }!
        let out = AutoCropEffect().apply(base)
        #expect(out.width == 4 && out.height == 4)
    }

    @Test func flipHorizontallyMirrors() {
        // left half red, right half transparent
        let base = EffectDraw.render(width: 10, height: 10) { context in
            context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 5, height: 10))
        }!
        var effect = FlipEffect()
        effect.horizontally = true
        let out = effect.apply(base)
        #expect(pixel(out, 2, 5).a == 0)
        #expect(pixel(out, 7, 5).a == 255)
    }
}

struct FilterTests {
    @Test func reflectionExtendsHeight() {
        var effect = ReflectionEffect()
        effect.percentage = 50
        let out = effect.apply(makeImage(width: 10, height: 10))
        #expect(out.height == 15)
    }

    @Test func shadowAutoResizeGrowsCanvas() {
        let out = ShadowEffect().apply(makeImage(width: 10, height: 10))
        // canvas + size*2 on both axes (default size 10)
        #expect(out.width == 30 && out.height == 30)
    }

    @Test func pixelateAveragesBlocks() {
        // half black, half white image, 8px blocks -> uniform gray blocks
        let base = EffectDraw.render(width: 8, height: 8) { context in
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 8))
        }!
        var effect = PixelateEffect()
        effect.size = 8
        let out = effect.apply(base)
        let p = pixel(out, 0, 0)
        #expect(abs(Int(p.r) - 127) <= 2)
    }

    @Test func edgeDetectFlatImageIsUniformGray() {
        let out = EdgeDetectEffect().apply(makeImage(color: (0.5, 0.5, 0.5, 1)))
        let p = pixel(out, 4, 4)
        #expect(p.r == 127 && p.g == 127 && p.b == 127) // kernel sums to 0 + offset 127
    }

    @Test func tornEdgeKeepsSizeAndClearsSomeEdgePixels() {
        var effect = TornEdgeEffect()
        effect.depth = 6
        effect.range = 4
        let out = effect.apply(makeImage(width: 40, height: 40))
        #expect(out.width == 40 && out.height == 40)
        #expect(pixel(out, 20, 20).a == 255) // center untouched
    }

    @Test func waveEdgeKeepsSize() {
        var effect = WaveEdgeEffect()
        effect.depth = 5
        effect.range = 10
        let out = effect.apply(makeImage(width: 40, height: 40))
        #expect(out.width == 40 && out.height == 40)
    }

    @Test func rgbSplitShiftsChannels() {
        var effect = RGBSplitEffect()
        effect.offsetRed = CSPoint(x: 2, y: 0)
        effect.offsetGreen = CSPoint()
        effect.offsetBlue = CSPoint(x: -2, y: 0)
        let out = effect.apply(makeImage(width: 10, height: 10, color: (1, 1, 1, 1)))
        #expect(out.width == 10)
        let p = pixel(out, 5, 5)
        #expect(p.r == 255 && p.g == 255 && p.b == 255)
    }

    @Test func presetChainAppliesInOrder() {
        var canvas = CanvasEffect()
        canvas.margin = CSPadding(left: 0, top: 0, right: 0, bottom: 10)
        var resize = ResizeEffect()
        resize.width = 5
        resize.height = 0
        let preset = ImageEffectPreset(name: "", effects: [canvas, resize])
        let out = preset.apply(makeImage(width: 10, height: 10))
        // canvas: 10x20, then resize to 5 wide keeping aspect: 5x10
        #expect(out.width == 5 && out.height == 10)
    }

    @Test func disabledEffectsAreSkipped() {
        var resize = ResizeEffect()
        resize.width = 5
        resize.height = 5
        resize.enabled = false
        let preset = ImageEffectPreset(name: "", effects: [resize])
        let out = preset.apply(makeImage(width: 10, height: 10))
        #expect(out.width == 10)
    }
}
