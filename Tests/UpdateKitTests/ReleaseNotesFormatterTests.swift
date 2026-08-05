// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import AppKit
import Testing
@testable import UpdateKit

struct ReleaseNotesFormatterTests {
    private let baseSize = NSFont.smallSystemFontSize + 1

    private func font(in rendered: NSAttributedString, at location: Int) -> NSFont? {
        rendered.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    }

    @Test func headingIsBoldAndLarger() {
        let rendered = ReleaseNotesFormatter.attributedString(fromMarkdown: "# Big News")
        #expect(rendered.string.contains("Big News"))
        #expect(!rendered.string.contains("#"))
        let headingFont = font(in: rendered, at: 0)
        #expect(headingFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect((headingFont?.pointSize ?? 0) > baseSize)
    }

    @Test func inlineMarkersAreConsumedAndStyled() {
        let rendered = ReleaseNotesFormatter.attributedString(
            fromMarkdown: "some **bold** and *italic* words")
        #expect(!rendered.string.contains("*"))
        let boldLocation = (rendered.string as NSString).range(of: "bold").location
        let italicLocation = (rendered.string as NSString).range(of: "italic").location
        #expect(font(in: rendered, at: boldLocation)?
            .fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(font(in: rendered, at: italicLocation)?
            .fontDescriptor.symbolicTraits.contains(.italic) == true)
        #expect(font(in: rendered, at: 0)?.fontDescriptor.symbolicTraits.contains(.bold) != true)
    }

    @Test func unorderedListGetsBullets() {
        let rendered = ReleaseNotesFormatter.attributedString(fromMarkdown: "- one\n- two")
        let lines = rendered.string.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines.allSatisfy { $0.hasPrefix("\u{2022} ") })
        #expect(!rendered.string.contains("- one"))
    }

    @Test func orderedListGetsNumbers() {
        let rendered = ReleaseNotesFormatter.attributedString(fromMarkdown: "1. first\n2. second")
        #expect(rendered.string.contains("1. first"))
        #expect(rendered.string.contains("2. second"))
    }

    @Test func listItemWithInlineStylingGetsOneBullet() {
        let rendered = ReleaseNotesFormatter.attributedString(
            fromMarkdown: "- **English** \u{2014} Native implementation")
        let bullets = rendered.string.filter { $0 == "\u{2022}" }.count
        #expect(bullets == 1)
    }

    @Test func codeBlockIsMonospaced() {
        let rendered = ReleaseNotesFormatter.attributedString(
            fromMarkdown: "```\nbrew upgrade\n```")
        let location = (rendered.string as NSString).range(of: "brew").location
        #expect(font(in: rendered, at: location)?.isFixedPitch == true)
    }

    @Test func longNotesAreNotTruncated() {
        // Regression guard: the alert used to clip notes at 500 characters.
        let body = (1...100).map { "Paragraph \($0) of the release notes." }
            .joined(separator: "\n\n")
        let rendered = ReleaseNotesFormatter.attributedString(fromMarkdown: body)
        #expect(rendered.length > 500)
        #expect(rendered.string.contains("Paragraph 100"))
    }

    @Test func crlfBodyRenders() {
        let rendered = ReleaseNotesFormatter.attributedString(
            fromMarkdown: "## Changes\r\n\r\n- Something new")
        #expect(rendered.string.contains("Changes"))
        #expect(rendered.string.contains("\u{2022} Something new"))
        #expect(!rendered.string.contains("#"))
    }

    @Test func plainTextSurvives() {
        let rendered = ReleaseNotesFormatter.attributedString(fromMarkdown: "Just a sentence.")
        #expect(rendered.string == "Just a sentence.")
    }
}
