// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
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
