// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// History.db import (the SQLite History table Windows ShareX v21 writes,
// which is also SwiftX's own schema — a store-written file must round-trip).

import Foundation
import Testing
@testable import HistoryKit

@MainActor
struct HistorySQLiteImportTests {
    @Test func importsRowsFromShareXDatabase() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareXImportTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("History.db")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // write through the store (same schema ShareX 21 uses)
        let source = HistoryStore(url: url)
        var first = HistoryItem()
        first.fileName = "chrome_2016-09-01_16-08-16.png"
        first.filePath = "D:\\Users\\Someone\\Documents\\ShareX\\Screenshots\\chrome.png"
        first.type = "Image"
        first.host = "Custom image uploader"
        first.url = "https://img.example.com/kbxel0.png"
        source.append(first)
        var second = HistoryItem()
        second.fileName = "clip.mp4"
        second.type = "File"
        second.host = "Amazon S3"
        second.tags = ["WindowTitle": "QuickTime"]
        source.append(second)

        let items = HistoryImport.items(fromSQLiteDatabase: url)
        #expect(items.count == 2)
        #expect(items[0].fileName == "chrome_2016-09-01_16-08-16.png")
        #expect(items[0].url == "https://img.example.com/kbxel0.png")
        #expect(items[0].host == "Custom image uploader")
        // Windows file paths survive verbatim (history shows them as text)
        #expect(items[0].filePath.hasPrefix("D:\\"))
        #expect(items[1].tags == ["WindowTitle": "QuickTime"])
        // imported items carry no row id — appendAll assigns fresh ones
        #expect(items.allSatisfy { $0.id == 0 })
    }

    @Test func missingOrInvalidDatabaseReturnsEmpty() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("nope-\(UUID().uuidString).db")
        #expect(HistoryImport.items(fromSQLiteDatabase: missing).isEmpty)
    }
}
