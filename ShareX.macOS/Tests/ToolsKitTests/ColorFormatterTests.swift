// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt

import Testing
@testable import ToolsKit

struct ColorFormatterTests {
    @Test func formatsOrangeInEveryClipboardFormat() {
        #expect(ColorFormatter.hex(r: 255, g: 128, b: 0) == "#FF8000")
        #expect(ColorFormatter.rgb(r: 255, g: 128, b: 0) == "255, 128, 0")
        #expect(ColorFormatter.hsb(r: 255, g: 128, b: 0) == "30°, 100%, 100%")
        #expect(ColorFormatter.cmyk(r: 255, g: 128, b: 0) == "0%, 50%, 100%, 0%")
        #expect(ColorFormatter.decimal(r: 255, g: 128, b: 0) == 0xFF8000)
    }

    @Test func edgeColorsDoNotDivideByZero() {
        #expect(ColorFormatter.hsb(r: 0, g: 0, b: 0) == "0°, 0%, 0%")
        #expect(ColorFormatter.cmyk(r: 0, g: 0, b: 0) == "0%, 0%, 0%, 100%")
        #expect(ColorFormatter.hsb(r: 255, g: 255, b: 255) == "0°, 0%, 100%")
        #expect(ColorFormatter.cmyk(r: 255, g: 255, b: 255) == "0%, 0%, 0%, 0%")
    }

    @Test func outOfRangeValuesAreClamped() {
        #expect(ColorFormatter.hex(r: 300, g: -5, b: 128) == "#FF0080")
        #expect(ColorFormatter.decimal(r: 256, g: 0, b: 0) == 0xFF0000)
    }
}
