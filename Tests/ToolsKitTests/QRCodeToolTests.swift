// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt

import Testing
@testable import ToolsKit

struct QRCodeToolTests {
    @Test func generatedCodeDecodesBackToItsText() throws {
        let text = "https://github.com/RetroHazard/SwiftX?test=1"
        let image = try #require(QRCodeTool.generate(text))
        #expect(image.width >= 256)
        let payloads = try QRCodeTool.decode(image)
        #expect(payloads == [text])
    }

    @Test func emptyTextGeneratesNothing() {
        #expect(QRCodeTool.generate("") == nil)
    }

    @Test func imageWithoutQRCodeDecodesToNothing() throws {
        let blank = try #require(OCRServiceTests.render(text: "no codes here"))
        #expect(try QRCodeTool.decode(blank).isEmpty)
    }
}
