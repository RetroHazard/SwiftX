// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt

import AppKit
import Testing
@testable import ToolsKit

struct OCRServiceTests {
    @Test func recognizesRenderedText() async throws {
        let image = try #require(Self.render(text: "SHAREX OCR 12345"))
        let result = try await OCRService.recognizeText(in: image)
        let normalized = result.uppercased()
        #expect(normalized.contains("SHAREX"))
        #expect(normalized.contains("12345"))
    }

    @Test func blankImageYieldsEmptyString() async throws {
        let image = try #require(Self.render(text: ""))
        let result = try await OCRService.recognizeText(in: image)
        #expect(result.isEmpty)
    }

    /// Black text on white, big enough that Vision can't miss it.
    static func render(text: String) -> CGImage? {
        let size = NSSize(width: 600, height: 120)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 48, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        NSString(string: text).draw(at: NSPoint(x: 20, y: 30), withAttributes: attributes)
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
