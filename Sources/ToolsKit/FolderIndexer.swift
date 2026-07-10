// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Folder index generator (C# ShareX.IndexerLib). Text and HTML outputs with
// the C# defaults: skip hidden, unlimited depth, show sizes, "|___" indent.
// ponytail: C# also emits XML/JSON - add if anyone asks.

import Foundation

public struct IndexerOptions: Sendable {
    public enum Format: String, CaseIterable, Sendable {
        case text = "Text"
        case html = "HTML"
    }

    public var format: Format = .html
    public var skipHidden = true
    /// 0 = unlimited (C# MaxDepthLevel)
    public var maxDepth = 0
    public var showSizes = true

    public init() {}
}

public enum FolderIndexer {
    private struct Entry {
        let name: String
        let size: Int64
        let children: [Entry]?  // nil = file
    }

    public static func index(folder: URL, options: IndexerOptions = .init()) throws -> String {
        let root = try scan(folder: folder, options: options, depth: 0)
        switch options.format {
        case .text:
            var lines = [root.name + sizeSuffix(root.size, options)]
            appendText(root.children ?? [], level: 1, options: options, into: &lines)
            return lines.joined(separator: "\n")
        case .html:
            var body = ""
            appendHTML([root], options: options, into: &body)
            return """
            <!DOCTYPE html>
            <html><head><meta charset="utf-8"><title>\(escape(root.name))</title>
            <style>body{font-family:-apple-system,sans-serif}ul{list-style:none;padding-left:1.2em}\
            .size{color:#888;font-size:.85em;margin-left:.5em}</style></head>
            <body>\(body)</body></html>
            """
        }
    }

    private static func scan(folder: URL, options: IndexerOptions, depth: Int) throws -> Entry {
        let contents = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: options.skipHidden ? [.skipsHiddenFiles] : []
        )
        var children: [Entry] = []
        for url in contents.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if values.isDirectory == true {
                if options.maxDepth > 0, depth + 1 >= options.maxDepth {
                    // depth limit: show the folder itself but not its contents
                    children.append(Entry(name: url.lastPathComponent, size: 0, children: []))
                } else {
                    children.append(try scan(folder: url, options: options, depth: depth + 1))
                }
            } else {
                children.append(Entry(name: url.lastPathComponent,
                                      size: Int64(values.fileSize ?? 0), children: nil))
            }
        }
        // folders first, like the C# indexer
        let ordered = children.filter { $0.children != nil } + children.filter { $0.children == nil }
        return Entry(name: folder.lastPathComponent,
                     size: ordered.map(\.size).reduce(0, +),
                     children: ordered)
    }

    private static func appendText(_ entries: [Entry], level: Int,
                                   options: IndexerOptions, into lines: inout [String]) {
        for entry in entries {
            // C# IndentationText default
            lines.append(String(repeating: "    ", count: level - 1) + "|___"
                + entry.name + sizeSuffix(entry.size, options))
            if let children = entry.children {
                appendText(children, level: level + 1, options: options, into: &lines)
            }
        }
    }

    private static func appendHTML(_ entries: [Entry], options: IndexerOptions, into body: inout String) {
        body += "<ul>"
        for entry in entries {
            let size = options.showSizes
                ? "<span class=\"size\">\(escape(formatSize(entry.size)))</span>" : ""
            if let children = entry.children {
                body += "<li><strong>\(escape(entry.name))</strong>\(size)"
                if !children.isEmpty {
                    appendHTML(children, options: options, into: &body)
                }
                body += "</li>"
            } else {
                body += "<li>\(escape(entry.name))\(size)</li>"
            }
        }
        body += "</ul>"
    }

    private static func sizeSuffix(_ size: Int64, _ options: IndexerOptions) -> String {
        options.showSizes ? " [\(formatSize(size))]" : ""
    }

    private static func formatSize(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
