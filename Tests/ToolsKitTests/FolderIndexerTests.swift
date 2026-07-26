// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import Foundation
import Testing
@testable import ToolsKit

struct FolderIndexerTests {
    /// root/{sub/{inner.txt}, file&one.txt, .hidden}
    static func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sharex-indexer-\(UUID().uuidString)")
        let sub = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: root.appendingPathComponent("file&one.txt"))
        try Data("world!".utf8).write(to: sub.appendingPathComponent("inner.txt"))
        try Data("shh".utf8).write(to: root.appendingPathComponent(".hidden"))
        return root
    }

    @Test func textOutputListsTreeAndSkipsHidden() throws {
        let root = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        var options = IndexerOptions()
        options.format = .text
        let output = try FolderIndexer.index(folder: root, options: options)
        #expect(output.contains("|___file&one.txt"))
        #expect(output.contains("|___sub"))
        #expect(output.contains("inner.txt"))
        #expect(!output.contains(".hidden"))
        // folder line comes before its contents
        let subIndex = try #require(output.range(of: "|___sub"))
        let innerIndex = try #require(output.range(of: "inner.txt"))
        #expect(subIndex.lowerBound < innerIndex.lowerBound)
    }

    @Test func maxDepthStopsDescending() throws {
        let root = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        var options = IndexerOptions()
        options.format = .text
        options.maxDepth = 1
        let output = try FolderIndexer.index(folder: root, options: options)
        #expect(output.contains("|___sub"))
        #expect(!output.contains("inner.txt"))
    }

    @Test func htmlOutputEscapesNamesAndNestsLists() throws {
        let root = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        let output = try FolderIndexer.index(folder: root)  // default: HTML
        #expect(output.contains("file&amp;one.txt"))
        #expect(output.contains("<strong>sub</strong>"))
        #expect(output.contains("<ul>"))
        #expect(output.hasPrefix("<!DOCTYPE html>"))
    }

    @Test func sizesCanBeHidden() throws {
        let root = try Self.makeTree()
        defer { try? FileManager.default.removeItem(at: root) }
        var options = IndexerOptions()
        options.format = .text
        options.showSizes = false
        let output = try FolderIndexer.index(folder: root, options: options)
        #expect(!output.contains("["))
    }
}
