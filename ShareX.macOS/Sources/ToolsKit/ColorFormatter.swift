// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Clipboard string formats for the color picker tools. Formats mirror the
// C# ColorPickerForm copy menu (hex, RGB, HSB, CMYK, decimal).

import Foundation

public enum ColorFormatter {
    /// "#RRGGBB"
    public static func hex(r: Int, g: Int, b: Int) -> String {
        String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
    }

    /// "255, 128, 64" - the C# CopyRGB format
    public static func rgb(r: Int, g: Int, b: Int) -> String {
        "\(clamp(r)), \(clamp(g)), \(clamp(b))"
    }

    /// "30°, 100%, 100%" (hue, saturation, brightness)
    public static func hsb(r: Int, g: Int, b: Int) -> String {
        let (h, s, v) = hsbComponents(r: r, g: g, b: b)
        return "\(Int(h.rounded()))°, \(Int((s * 100).rounded()))%, \(Int((v * 100).rounded()))%"
    }

    /// "0%, 50%, 100%, 0%" (cyan, magenta, yellow, key)
    public static func cmyk(r: Int, g: Int, b: Int) -> String {
        let rf = Double(clamp(r)) / 255, gf = Double(clamp(g)) / 255, bf = Double(clamp(b)) / 255
        let k = 1 - max(rf, gf, bf)
        // pure black: avoid 0/0
        let c = k >= 1 ? 0 : (1 - rf - k) / (1 - k)
        let m = k >= 1 ? 0 : (1 - gf - k) / (1 - k)
        let y = k >= 1 ? 0 : (1 - bf - k) / (1 - k)
        return [c, m, y, k].map { "\(Int(($0 * 100).rounded()))%" }.joined(separator: ", ")
    }

    /// RGB packed into one integer, like C#'s decimal copy (r<<16 | g<<8 | b)
    public static func decimal(r: Int, g: Int, b: Int) -> Int {
        (clamp(r) << 16) | (clamp(g) << 8) | clamp(b)
    }

    static func hsbComponents(r: Int, g: Int, b: Int) -> (h: Double, s: Double, v: Double) {
        let rf = Double(clamp(r)) / 255, gf = Double(clamp(g)) / 255, bf = Double(clamp(b)) / 255
        let maxC = max(rf, gf, bf), minC = min(rf, gf, bf)
        let delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            switch maxC {
            case rf: h = 60 * ((gf - bf) / delta).truncatingRemainder(dividingBy: 6)
            case gf: h = 60 * ((bf - rf) / delta + 2)
            default: h = 60 * ((rf - gf) / delta + 4)
            }
            if h < 0 { h += 360 }
        }
        return (h, maxC == 0 ? 0 : delta / maxC, maxC)
    }

    private static func clamp(_ value: Int) -> Int { min(255, max(0, value)) }
}
