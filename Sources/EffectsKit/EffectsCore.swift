// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Effect chain core. Presets serialize to the C# ImageEffectsLib JSON shape:
// PascalCase keys, "$type" holding the bare C# class name, and .sxie files
// are ZIP archives containing Config.json (plus optional image assets).

import CoreGraphics
import Foundation
import SharedKit

public enum EffectCategory: String, CaseIterable, Sendable {
    case drawings = "Drawings"
    case manipulations = "Manipulations"
    case adjustments = "Adjustments"
    case filters = "Filters"

    /// Localized display label; the rawValue stays the stable identifier.
    public var localizedName: String {
        switch self {
        case .drawings: return L10n.t("effects.core.category.drawings")
        case .manipulations: return L10n.t("effects.core.category.manipulations")
        case .adjustments: return L10n.t("effects.core.category.adjustments")
        case .filters: return L10n.t("effects.core.category.filters")
        }
    }
}

public protocol ImageEffecting: Codable {
    /// The C# class name, used as the JSON "$type" discriminator.
    static var typeName: String { get }
    static var category: EffectCategory { get }
    init()
    var enabled: Bool { get set }
    var name: String { get set }
    func apply(_ image: CGImage) -> CGImage
}

public extension ImageEffecting {
    /// The user-set name wins; otherwise the localized effect-type name.
    /// Presets persist `name` and the "$type" discriminator, never this value.
    var displayName: String { name.isEmpty ? Self.localizedTypeName : name }

    /// Localized display name for the effect type. `typeName` itself is the
    /// persisted JSON "$type" discriminator and must never be localized.
    static var localizedTypeName: String {
        L10n.t(EffectTypeL10n.key(for: typeName))
    }
}

/// Maps the persisted C# "$type" names to localization keys. Unknown type
/// names fall through L10n as themselves, so the raw name still shows.
enum EffectTypeL10n {
    private static let keys: [String: String] = [
        // Adjustments
        "Alpha": "effects.filter.alpha",
        "BlackWhite": "effects.filter.black_white",
        "Brightness": "effects.filter.brightness",
        "Colorize": "effects.filter.colorize",
        "Contrast": "effects.filter.contrast",
        "Gamma": "effects.filter.gamma",
        "Grayscale": "effects.filter.grayscale",
        "Hue": "effects.filter.hue",
        "Inverse": "effects.filter.inverse",
        "MatrixColor": "effects.filter.matrix_color",
        "Polaroid": "effects.filter.polaroid",
        "ReplaceColor": "effects.filter.replace_color",
        "Saturation": "effects.filter.saturation",
        "SelectiveColor": "effects.filter.selective_color",
        "Sepia": "effects.filter.sepia",
        // Filters
        "Blur": "effects.filter.blur",
        "ColorDepth": "effects.filter.color_depth",
        "EdgeDetect": "effects.filter.edge_detect",
        "Emboss": "effects.filter.emboss",
        "GaussianBlur": "effects.filter.gaussian_blur",
        "Glow": "effects.filter.glow",
        "MatrixConvolution": "effects.filter.matrix_convolution",
        "MeanRemoval": "effects.filter.mean_removal",
        "Outline": "effects.filter.outline",
        "Pixelate": "effects.filter.pixelate",
        "Reflection": "effects.filter.reflection",
        "RGBSplit": "effects.filter.rgb_split",
        "Shadow": "effects.filter.shadow",
        "Sharpen": "effects.filter.sharpen",
        "Slice": "effects.filter.slice",
        "Smooth": "effects.filter.smooth",
        "TornEdge": "effects.filter.torn_edge",
        "WaveEdge": "effects.filter.wave_edge",
        // Manipulations
        "AutoCrop": "effects.filter.auto_crop",
        "Canvas": "effects.filter.canvas",
        "Crop": "effects.filter.crop",
        "Flip": "effects.filter.flip",
        "ForceProportions": "effects.filter.force_proportions",
        "Resize": "effects.filter.resize",
        "Rotate": "effects.filter.rotate",
        "RoundedCorners": "effects.filter.rounded_corners",
        "Scale": "effects.filter.scale",
        "Skew": "effects.filter.skew",
        // Drawings
        "DrawBackground": "effects.filter.draw_background",
        "DrawBackgroundImage": "effects.filter.draw_background_image",
        "DrawBorder": "effects.filter.draw_border",
        "DrawCheckerboard": "effects.filter.draw_checkerboard",
        "DrawImage": "effects.filter.draw_image",
        "DrawParticles": "effects.filter.draw_particles",
        "DrawText": "effects.filter.draw_text",
        "DrawTextEx": "effects.filter.draw_text_ex"
    ]

    static func key(for typeName: String) -> String {
        keys[typeName] ?? typeName
    }
}

// MARK: - JSON plumbing

/// PascalCase JSON keys <-> camelCase Swift properties (first letter only,
/// which is how every C# effect property maps).
private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { stringValue = "\(intValue)"; self.intValue = intValue }
}

enum EffectJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .custom { keys in
            let key = keys.last!.stringValue
            return AnyKey(stringValue: key.prefix(1).uppercased() + key.dropFirst())
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { keys in
            let key = keys.last!.stringValue
            return AnyKey(stringValue: key.prefix(1).lowercased() + key.dropFirst())
        }
        return decoder
    }()
}

public extension ImageEffecting {
    /// Decodes from a JSON object, filling missing keys from a default
    /// instance so partial C# exports (DefaultValueHandling.Ignore) work.
    /// Public so the app's parameter editor can round-trip field edits.
    static func decode(mergedWith dict: [String: Any]) throws -> Self {
        let defaults = try JSONSerialization.jsonObject(
            with: EffectJSON.encoder.encode(Self())) as! [String: Any]
        var merged = defaults
        for (key, value) in dict where key != "$type" { merged[key] = value }
        return try EffectJSON.decoder.decode(
            Self.self, from: JSONSerialization.data(withJSONObject: merged))
    }

    func encodeWithType() throws -> [String: Any] {
        var dict = try JSONSerialization.jsonObject(
            with: EffectJSON.encoder.encode(self)) as! [String: Any]
        dict["$type"] = Self.typeName
        return dict
    }
}

// MARK: - Registry

public enum EffectRegistry {
    public static let allTypes: [any ImageEffecting.Type] = [
        // Adjustments
        AlphaEffect.self, BlackWhiteEffect.self, BrightnessEffect.self, ColorizeEffect.self,
        ContrastEffect.self, GammaEffect.self, GrayscaleEffect.self, HueEffect.self,
        InverseEffect.self, MatrixColorEffect.self, PolaroidEffect.self, ReplaceColorEffect.self,
        SaturationEffect.self, SelectiveColorEffect.self, SepiaEffect.self,
        // Filters
        BlurEffect.self, ColorDepthEffect.self, EdgeDetectEffect.self, EmbossEffect.self,
        GaussianBlurEffect.self, GlowEffect.self, MatrixConvolutionEffect.self,
        MeanRemovalEffect.self, OutlineEffect.self, PixelateEffect.self, ReflectionEffect.self,
        RGBSplitEffect.self, ShadowEffect.self, SharpenEffect.self, SliceEffect.self,
        SmoothEffect.self, TornEdgeEffect.self, WaveEdgeEffect.self,
        // Manipulations
        AutoCropEffect.self, CanvasEffect.self, CropEffect.self, FlipEffect.self,
        ForceProportionsEffect.self, ResizeEffect.self, RotateEffect.self,
        RoundedCornersEffect.self, ScaleEffect.self, SkewEffect.self,
        // Drawings
        DrawBackgroundEffect.self, DrawBackgroundImageEffect.self, DrawBorderEffect.self,
        DrawCheckerboardEffect.self, DrawImageEffect.self, DrawParticlesEffect.self,
        DrawTextEffect.self, DrawTextExEffect.self
    ]

    public static func type(named name: String) -> (any ImageEffecting.Type)? {
        allTypes.first { $0.typeName == name }
    }

    public static func types(in category: EffectCategory) -> [any ImageEffecting.Type] {
        allTypes.filter { $0.category == category }
    }
}

// MARK: - Preset

public struct ImageEffectPreset {
    public var name = ""
    public var effects: [any ImageEffecting] = []

    public init(name: String = "", effects: [any ImageEffecting] = []) {
        self.name = name
        self.effects = effects
    }

    public func apply(_ image: CGImage) -> CGImage {
        effects.filter(\.enabled).reduce(image) { $1.apply($0) }
    }

    /// ShareX's default preset: 30px bottom margin + gradient text watermark.
    public static func defaultPreset() -> ImageEffectPreset {
        var canvas = CanvasEffect()
        canvas.margin = CSPadding(left: 0, top: 0, right: 0, bottom: 30)
        var text = DrawTextEffect()
        text.offset = CSPoint(x: 0, y: 0)
        text.useGradient = true
        return ImageEffectPreset(name: "Preset", effects: [canvas, text])
    }

    // MARK: JSON

    public func configJSON() throws -> Data {
        let dict: [String: Any] = [
            "Name": name,
            "Effects": try effects.map { try $0.encodeWithType() }
        ]
        return try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    }

    public static func fromConfigJSON(_ data: Data) throws -> ImageEffectPreset {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EffectsError.invalidConfig
        }
        var preset = ImageEffectPreset(name: dict["Name"] as? String ?? "")
        for entry in dict["Effects"] as? [[String: Any]] ?? [] {
            guard let typeName = entry["$type"] as? String,
                  let type = EffectRegistry.type(named: typeName) else { continue } // skip unknown effects
            preset.effects.append(try type.decode(mergedWith: entry))
        }
        return preset
    }

    // MARK: .sxie (ZIP with Config.json)

    public func exportSXIE(to url: URL) throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("sxie-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try configJSON().write(to: staging.appendingPathComponent("Config.json"))
        try? FileManager.default.removeItem(at: url)
        try Self.runZipTool("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", staging.path, url.path])
    }

    public static func importSXIE(from url: URL) throws -> ImageEffectPreset {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("sxie-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try runZipTool("/usr/bin/ditto", ["-x", "-k", url.path, staging.path])
        // Config.json may sit at the root or inside a folder
        guard let config = FileManager.default
            .enumerator(at: staging, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL })
            .first(where: { $0.lastPathComponent.lowercased() == "config.json" })
        else { throw EffectsError.invalidConfig }
        var preset = try fromConfigJSON(Data(contentsOf: config))
        if preset.name.isEmpty {
            preset.name = url.deletingPathExtension().lastPathComponent
        }
        return preset
    }

    private static func runZipTool(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw EffectsError.packagingFailed }
    }
}

public enum EffectsError: LocalizedError {
    case invalidConfig
    case packagingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidConfig: return L10n.t("effects.core.error.invalid_config")
        case .packagingFailed: return L10n.t("effects.core.error.packaging_failed")
        }
    }
}

// MARK: - Shared drawing helpers

enum EffectDraw {
    /// Top-left-origin sRGB context; body draws, returns the composed image.
    static func render(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage? {
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        // flip so drawing code can think in top-left origin like GDI+
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        body(context)
        return context.makeImage()
    }

    /// Draws an image into a top-left-origin rect inside a flipped context.
    static func draw(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY + rect.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    /// Extends the canvas by a margin, optionally filled (ImageHelpers.AddCanvas).
    static func addCanvas(_ image: CGImage, margin: CSPadding, color: CSColor = .transparent) -> CGImage {
        let width = image.width + margin.horizontal
        let height = image.height + margin.vertical
        guard width > 0, height > 0 else { return image }
        return render(width: width, height: height) { context in
            if color.a > 0 {
                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
            draw(image, in: CGRect(x: margin.left, y: margin.top,
                                   width: image.width, height: image.height), context: context)
        } ?? image
    }

    /// Fills a top-left-origin path with the image as a texture (GDI TextureBrush).
    static func fillPath(_ path: CGPath, with image: CGImage, background: CSColor = .transparent) -> CGImage {
        render(width: image.width, height: image.height) { context in
            if background.a > 0 {
                context.setFillColor(background.cgColor)
                context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            context.addPath(path)
            context.clip()
            draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height), context: context)
        } ?? image
    }
}
