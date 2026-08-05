// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Renders GitHub release-notes markdown into a styled NSAttributedString for
// the update alert. Foundation's AttributedString(markdown:) with .full syntax
// emits PresentationIntent block attributes that NSTextView does not style on
// its own, so this walks the runs and applies fonts, bullets, and indents.
// GitHub-flavored constructs Foundation cannot parse (tables, task-list
// checkboxes) degrade to plain paragraphs.

import AppKit

public enum ReleaseNotesFormatter {
    public static func attributedString(
        fromMarkdown markdown: String,
        baseFontSize: CGFloat = NSFont.smallSystemFontSize + 1
    ) -> NSAttributedString {
        // GitHub API bodies use CRLF; Foundation's parser wants LF.
        let text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible)
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: baseFontSize),
                .foregroundColor: NSColor.labelColor,
            ])
        }

        let result = NSMutableAttributedString()
        var previousBlockIdentity: [Int]?
        var emittedListItems = Set<Int>()

        for run in parsed.runs {
            let runText = String(parsed[run.range].characters)
            if runText.isEmpty { continue }

            let block = BlockTraits(run.presentationIntent, baseFontSize: baseFontSize)
            var attributes: [NSAttributedString.Key: Any] = [
                .font: block.font,
                .foregroundColor: block.color,
                .paragraphStyle: block.paragraphStyle,
            ]

            // .full syntax strips the newlines between blocks; reinsert one at
            // each block boundary and let paragraphSpacing provide the gap.
            if let previous = previousBlockIdentity, previous != block.identity {
                result.append(NSAttributedString(string: "\n", attributes: attributes))
            }
            previousBlockIdentity = block.identity

            // A list item spans multiple runs when it contains inline styling,
            // so the bullet is emitted once per item identity, not per run.
            if let itemIdentity = block.listItemIdentity,
               emittedListItems.insert(itemIdentity).inserted {
                result.append(NSAttributedString(string: block.listItemPrefix,
                                                 attributes: attributes))
            }

            attributes[.font] = Self.applyingInlineIntent(run.inlinePresentationIntent,
                                                          to: block.font)
            if run.inlinePresentationIntent?.contains(.strikethrough) == true {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            result.append(NSAttributedString(string: runText, attributes: attributes))
        }
        return result
    }

    // MARK: - Block-level styling

    private struct BlockTraits {
        let font: NSFont
        let color: NSColor
        let paragraphStyle: NSParagraphStyle
        /// Identities of every block component; any change marks a block
        /// break. Compared as a whole so the (undocumented) ordering of
        /// PresentationIntent.components never matters.
        let identity: [Int]
        let listItemIdentity: Int?
        let listItemPrefix: String

        init(_ intent: PresentationIntent?, baseFontSize: CGFloat) {
            var headerLevel = 0
            var isCodeBlock = false
            var isBlockQuote = false
            var isOrderedList = false
            var inList = false
            var itemIdentity: Int?
            var ordinal = 0

            for component in intent?.components ?? [] {
                switch component.kind {
                case .header(let level): headerLevel = level
                case .codeBlock: isCodeBlock = true
                case .blockQuote: isBlockQuote = true
                case .listItem(let itemOrdinal):
                    itemIdentity = component.identity
                    ordinal = itemOrdinal
                case .orderedList: isOrderedList = true; inList = true
                case .unorderedList: inList = true
                default: break
                }
            }

            if headerLevel > 0 {
                let size = baseFontSize + max(0, CGFloat(3 - headerLevel) * 2)
                font = NSFont.boldSystemFont(ofSize: size)
            } else if isCodeBlock {
                font = NSFont.monospacedSystemFont(ofSize: baseFontSize - 1, weight: .regular)
            } else {
                font = NSFont.systemFont(ofSize: baseFontSize)
            }
            color = isBlockQuote ? .secondaryLabelColor : .labelColor

            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 6
            if inList || itemIdentity != nil {
                // Wrapped lines align past the bullet.
                paragraph.firstLineHeadIndent = 8
                paragraph.headIndent = 20
            } else if isCodeBlock || isBlockQuote {
                paragraph.firstLineHeadIndent = 12
                paragraph.headIndent = 12
            }
            paragraphStyle = paragraph

            identity = (intent?.components ?? []).map(\.identity)
            listItemIdentity = itemIdentity
            listItemPrefix = itemIdentity == nil ? ""
                : (isOrderedList ? "\(ordinal). " : "\u{2022} ")
        }
    }

    // MARK: - Inline-level styling

    private static func applyingInlineIntent(_ intent: InlinePresentationIntent?,
                                             to font: NSFont) -> NSFont {
        guard let intent else { return font }
        var result = font
        if intent.contains(.code) {
            result = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
        }
        if intent.contains(.stronglyEmphasized) {
            result = applying(trait: .bold, to: result)
        }
        if intent.contains(.emphasized) {
            result = applying(trait: .italic, to: result)
        }
        return result
    }

    private static func applying(trait: NSFontDescriptor.SymbolicTraits,
                                 to font: NSFont) -> NSFont {
        let descriptor = font.fontDescriptor
            .withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
}
