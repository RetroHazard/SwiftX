// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Scalar types that round-trip the C# ImageEffectsLib JSON, where .NET
// TypeConverters serialize values as strings: Color "235, 235, 235" or
// "125, 0, 0, 0" (ARGB) or a named color, Point "5, 5", Size "100, 50",
// Padding "l, t, r, b", Font "Arial, 11.25pt, style=Bold".

import AppKit

// MARK: - Color

public struct CSColor: Codable, Equatable, Sendable {
    public var r: UInt8 = 0
    public var g: UInt8 = 0
    public var b: UInt8 = 0
    public var a: UInt8 = 255

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public static let transparent = CSColor(r: 255, g: 255, b: 255, a: 0)
    public static let black = CSColor(r: 0, g: 0, b: 0)
    public static let white = CSColor(r: 255, g: 255, b: 255)
    public static let red = CSColor(r: 255, g: 0, b: 0)
    public static let lightGray = CSColor(r: 211, g: 211, b: 211)

    // ponytail: the handful of names ShareX defaults actually use; extend if a preset imports another
    private static let named: [String: CSColor] = [
        "transparent": .transparent, "black": .black, "white": .white, "red": .red,
        "lightgray": .lightGray, "green": CSColor(r: 0, g: 128, b: 0),
        "blue": CSColor(r: 0, g: 0, b: 255), "yellow": CSColor(r: 255, g: 255, b: 0),
        "gray": CSColor(r: 128, g: 128, b: 128), "darkgray": CSColor(r: 169, g: 169, b: 169),
        "orange": CSColor(r: 255, g: 165, b: 0), "purple": CSColor(r: 128, g: 0, b: 128)
    ]

    public init(string: String) {
        let parts = string.split(separator: ",").compactMap { UInt8($0.trimmingCharacters(in: .whitespaces)) }
        switch parts.count {
        case 3: self = CSColor(r: parts[0], g: parts[1], b: parts[2])
        case 4: self = CSColor(r: parts[1], g: parts[2], b: parts[3], a: parts[0]) // A, R, G, B
        default: self = Self.named[string.trimmingCharacters(in: .whitespaces).lowercased()] ?? .black
        }
    }

    public var stringValue: String {
        a == 255 ? "\(r), \(g), \(b)" : "\(a), \(r), \(g), \(b)"
    }

    public init(from decoder: Decoder) throws {
        self.init(string: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(stringValue)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }

    public var nsColor: NSColor { NSColor(cgColor: cgColor) ?? .black }
}

// MARK: - Geometry strings

public struct CSPoint: Codable, Equatable, Sendable {
    public var x = 0
    public var y = 0
    public init(x: Int = 0, y: Int = 0) { self.x = x; self.y = y }

    public init(from decoder: Decoder) throws {
        let parts = try decoder.singleValueContainer().decode(String.self)
            .split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2 { x = parts[0]; y = parts[1] }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("\(x), \(y)")
    }
}

public struct CSSize: Codable, Equatable, Sendable {
    public var width = 0
    public var height = 0
    public init(width: Int = 0, height: Int = 0) { self.width = width; self.height = height }

    public init(from decoder: Decoder) throws {
        let parts = try decoder.singleValueContainer().decode(String.self)
            .split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2 { width = parts[0]; height = parts[1] }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("\(width), \(height)")
    }
}

/// C# Padding serializes as "left, top, right, bottom".
public struct CSPadding: Codable, Equatable, Sendable {
    public var left = 0
    public var top = 0
    public var right = 0
    public var bottom = 0

    public init(left: Int = 0, top: Int = 0, right: Int = 0, bottom: Int = 0) {
        self.left = left; self.top = top; self.right = right; self.bottom = bottom
    }

    public var horizontal: Int { left + right }
    public var vertical: Int { top + bottom }
    public var all: Int { left + top + right + bottom }

    public init(from decoder: Decoder) throws {
        let parts = try decoder.singleValueContainer().decode(String.self)
            .split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 4 { left = parts[0]; top = parts[1]; right = parts[2]; bottom = parts[3] }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("\(left), \(top), \(right), \(bottom)")
    }
}

// MARK: - Font

public struct CSFont: Codable, Equatable, Sendable {
    public var family = "Arial"
    public var size: Double = 11.25
    public var bold = false
    public var italic = false

    public init(family: String = "Arial", size: Double = 11.25, bold: Bool = false, italic: Bool = false) {
        self.family = family; self.size = size; self.bold = bold; self.italic = italic
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        for (index, piece) in raw.split(separator: ",").enumerated() {
            let part = piece.trimmingCharacters(in: .whitespaces)
            if index == 0 {
                family = part
            } else if part.hasSuffix("pt"), let value = Double(part.dropLast(2)) {
                size = value
            } else if part.lowercased().contains("style=") || bold || italic || index > 1 {
                let styles = part.replacingOccurrences(of: "style=", with: "").lowercased()
                if styles.contains("bold") { bold = true }
                if styles.contains("italic") { italic = true }
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var styles: [String] = []
        if bold { styles.append("Bold") }
        if italic { styles.append("Italic") }
        let suffix = styles.isEmpty ? "" : ", style=\(styles.joined(separator: ", "))"
        var container = encoder.singleValueContainer()
        try container.encode("\(family), \(size.formatted(.number.precision(.fractionLength(0...2))))pt\(suffix)")
    }

    public var nsFont: NSFont {
        var font = NSFont(name: family, size: size) ?? .systemFont(ofSize: size)
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        if !traits.isEmpty {
            font = NSFontManager.shared.convert(font, toHaveTrait: traits)
        }
        return font
    }
}

// MARK: - Gradient

/// C# System.Drawing.Drawing2D.LinearGradientMode raw values.
public enum GradientType: Int, Codable, Sendable {
    case horizontal = 0, vertical = 1, forwardDiagonal = 2, backwardDiagonal = 3
}

public struct GradientStop: Codable, Equatable, Sendable {
    public var color = CSColor.black
    /// 0-100 like the C# Location percentage.
    public var location: Float = 0
    public init(color: CSColor, location: Float) { self.color = color; self.location = location }
    public init() {}
}

public struct GradientInfo: Codable, Equatable, Sendable {
    public var type = GradientType.vertical
    public var colors: [GradientStop] = []
    public init() {}
    public init(type: GradientType, colors: [GradientStop]) { self.type = type; self.colors = colors }

    public var isValid: Bool { !colors.isEmpty }

    /// ShareX DrawText's default blue gradient.
    public static let defaultText = GradientInfo(type: .vertical, colors: [
        GradientStop(color: CSColor(r: 68, g: 120, b: 194), location: 0),
        GradientStop(color: CSColor(r: 13, g: 58, b: 122), location: 50),
        GradientStop(color: CSColor(r: 6, g: 36, b: 78), location: 50),
        GradientStop(color: CSColor(r: 23, g: 89, b: 174), location: 100)
    ])

    /// Fills a rect in a top-left-origin ("flipped") context.
    func fill(_ rect: CGRect, in context: CGContext) {
        let sorted = colors.sorted { $0.location < $1.location }
        guard let first = sorted.first else { return }
        guard sorted.count > 1 else {
            context.setFillColor(first.color.cgColor)
            context.fill(rect)
            return
        }
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: sorted.map(\.color.cgColor) as CFArray,
            locations: sorted.map { CGFloat($0.location) / 100 }
        ) else { return }
        let (start, end): (CGPoint, CGPoint)
        switch type {
        case .horizontal:
            (start, end) = (CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.midY))
        case .vertical:
            (start, end) = (CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.midX, y: rect.maxY))
        case .forwardDiagonal:
            (start, end) = (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
        case .backwardDiagonal:
            (start, end) = (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY))
        }
        context.saveGState()
        context.clip(to: rect)
        context.drawLinearGradient(gradient, start: start, end: end, options: [])
        context.restoreGState()
    }
}

// MARK: - Windows enums (raw values match System.Windows.Forms / System.Drawing)

/// AnchorStyles flags: Top=1, Bottom=2, Left=4, Right=8.
public struct AnchorSides: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let top = AnchorSides(rawValue: 1)
    public static let bottom = AnchorSides(rawValue: 2)
    public static let left = AnchorSides(rawValue: 4)
    public static let right = AnchorSides(rawValue: 8)
    public static let all: AnchorSides = [.top, .bottom, .left, .right]

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(Int.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// System.Drawing.ContentAlignment raw values.
public enum ContentAlignment: Int, Codable, CaseIterable, Sendable {
    case topLeft = 1, topCenter = 2, topRight = 4
    case middleLeft = 16, middleCenter = 32, middleRight = 64
    case bottomLeft = 256, bottomCenter = 512, bottomRight = 1024

    /// Origin for a box of `size` inside `bounds` (top-left origin coordinates).
    func origin(of size: CGSize, in bounds: CGSize, offset: CSPoint) -> CGPoint {
        let x: CGFloat, y: CGFloat
        switch self {
        case .topLeft, .middleLeft, .bottomLeft: x = CGFloat(offset.x)
        case .topCenter, .middleCenter, .bottomCenter: x = (bounds.width - size.width) / 2 + CGFloat(offset.x)
        case .topRight, .middleRight, .bottomRight: x = bounds.width - size.width - CGFloat(offset.x)
        }
        switch self {
        case .topLeft, .topCenter, .topRight: y = CGFloat(offset.y)
        case .middleLeft, .middleCenter, .middleRight: y = (bounds.height - size.height) / 2 + CGFloat(offset.y)
        case .bottomLeft, .bottomCenter, .bottomRight: y = bounds.height - size.height - CGFloat(offset.y)
        }
        return CGPoint(x: x, y: y)
    }
}

/// System.Drawing.Drawing2D.DashStyle raw values.
public enum DashStyle: Int, Codable, Sendable {
    case solid = 0, dash = 1, dot = 2, dashDot = 3, dashDotDot = 4, custom = 5

    /// GDI+ dash patterns are multiples of the pen width.
    func pattern(width: CGFloat) -> [CGFloat] {
        switch self {
        case .solid, .custom: return []
        case .dash: return [3 * width, width]
        case .dot: return [width, width]
        case .dashDot: return [3 * width, width, width, width]
        case .dashDotDot: return [3 * width, width, width, width, width, width]
        }
    }
}
