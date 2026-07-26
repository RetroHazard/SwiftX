// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import Foundation
import SQLite3
import Testing
@testable import HistoryKit

@MainActor
struct HistoryKitTests {
    private func withStore(_ body: (HistoryStore) throws -> Void) rethrows {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareXTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("History.db")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try body(HistoryStore(url: url))
    }

    private func makeItem(fileName: String, url: String = "") -> HistoryItem {
        var item = HistoryItem()
        item.fileName = fileName
        item.filePath = "/tmp/\(fileName)"
        item.url = url
        item.host = url.isEmpty ? "File" : "Imgur"
        item.tags = ["WindowTitle": "Safari"]
        return item
    }

    @Test func appendAssignsIdAndPersists() {
        withStore { store in
            let inserted = store.append(makeItem(fileName: "a.png"))
            #expect(inserted.id > 0)
            #expect(store.count() == 1)

            let loaded = store.recent()
            #expect(loaded.count == 1)
            #expect(loaded[0].fileName == "a.png")
            #expect(loaded[0].tags == ["WindowTitle": "Safari"])
        }
    }

    @Test func recentIsNewestFirst() {
        withStore { store in
            store.append(makeItem(fileName: "first.png"))
            store.append(makeItem(fileName: "second.png"))
            let items = store.recent()
            #expect(items.map(\.fileName) == ["second.png", "first.png"])
        }
    }

    @Test func searchFiltersByNameURLAndHost() {
        withStore { store in
            store.append(makeItem(fileName: "cat.png"))
            store.append(makeItem(fileName: "dog.png", url: "https://i.imgur.com/x.png"))

            #expect(store.recent(search: "cat").map(\.fileName) == ["cat.png"])
            #expect(store.recent(search: "imgur.com").map(\.fileName) == ["dog.png"])
            #expect(store.recent(search: "Imgur").count == 1) // host match
            #expect(store.recent(search: "zzz").isEmpty)
        }
    }

    @Test func updateUploadURLsTargetsNewestRowForFile() {
        withStore { store in
            store.append(makeItem(fileName: "a.png"))
            store.append(makeItem(fileName: "a.png"))
            store.updateUploadURLs(filePath: "/tmp/a.png", host: "S3", url: "https://s3/a.png")

            let items = store.recent()
            #expect(items[0].url == "https://s3/a.png") // newest updated
            #expect(items[0].host == "S3")
            #expect(items[1].url == "") // older untouched
        }
    }

    @Test func limitIsRespected() {
        withStore { store in
            for i in 0..<10 {
                store.append(makeItem(fileName: "\(i).png"))
            }
            #expect(store.recent(limit: 3).count == 3)
        }
    }

    @Test func favoriteRoundTrip() {
        withStore { store in
            let item = store.append(makeItem(fileName: "a.png"))
            #expect(!item.isFavorite)

            store.setFavorite(id: item.id, true)
            let favorited = store.recent()[0]
            #expect(favorited.isFavorite)
            #expect(favorited.tags["WindowTitle"] == "Safari") // other tags preserved

            store.setFavorite(id: item.id, false)
            #expect(!store.recent()[0].isFavorite)
        }
    }

    @Test func favoritesOnlyFilter() {
        withStore { store in
            let a = store.append(makeItem(fileName: "a.png"))
            store.append(makeItem(fileName: "b.png"))
            store.setFavorite(id: a.id, true)

            let favorites = store.recent(favoritesOnly: true)
            #expect(favorites.map(\.fileName) == ["a.png"])
        }
    }

    @Test func dateRangeFilter() {
        withStore { store in
            var old = makeItem(fileName: "old.png")
            old.date = Date(timeIntervalSinceNow: -86400 * 10)
            store.append(old)
            store.append(makeItem(fileName: "new.png"))

            let recent = store.recent(from: Date(timeIntervalSinceNow: -86400 * 7))
            #expect(recent.map(\.fileName) == ["new.png"])
            #expect(store.recent().count == 2)
        }
    }

    @Test func searchMatchesTagValues() {
        withStore { store in
            store.append(makeItem(fileName: "a.png")) // tags: WindowTitle = Safari
            var plain = makeItem(fileName: "b.png")
            plain.tags = [:]
            store.append(plain)

            // C# SearchInTags: the search box matches window title / process name
            #expect(store.recent(search: "Safari").map(\.fileName) == ["a.png"])
        }
    }

    @Test func importsWindowsJSONStream() {
        // History.json is comma-separated objects with no array brackets,
        // C# "o" dates, and Favorite serialized with a null value
        let json = """
        {
          "FileName": "a.png",
          "FilePath": "C:\\\\Screenshots\\\\a.png",
          "DateTime": "2024-03-15T10:30:45.1234567",
          "Type": "Image",
          "Host": "Imgur",
          "URL": "https://i.imgur.com/a.png",
          "Tags": { "WindowTitle": "Notepad", "ProcessName": "notepad", "Favorite": null }
        },
        {
          "FileName": "b.txt",
          "DateTime": "2023-01-01T00:00:00Z",
          "Type": "Text"
        }
        """
        let items = HistoryImport.items(fromJSON: json)
        #expect(items.count == 2)
        #expect(items[0].fileName == "a.png")
        #expect(items[0].url == "https://i.imgur.com/a.png")
        #expect(items[0].tags["WindowTitle"] == "Notepad")
        #expect(items[0].isFavorite) // null-valued tag still counts as present
        #expect(Calendar.current.component(.year, from: items[0].date) == 2024)
        #expect(items[1].type == "Text")
        #expect(HistoryImport.items(fromJSON: "not json").isEmpty)
    }

    @Test func importsWindowsXMLFragmentStream() {
        // History.xml is root-level <HistoryItem> fragments with no document root
        let xml = """
        <HistoryItem>
            <Filename>a.png</Filename>
            <Filepath>C:\\Screenshots\\a.png</Filepath>
            <DateTimeUtc>2015-08-30T12:36:00.0000000Z</DateTimeUtc>
            <Type>Image</Type>
            <Host>Imgur</Host>
            <URL>https://i.imgur.com/a.png</URL>
        </HistoryItem>
        <HistoryItem>
            <Filename>b.png</Filename>
            <Type>Image</Type>
        </HistoryItem>
        """
        let items = HistoryImport.items(fromXML: xml)
        #expect(items.count == 2)
        #expect(items[0].fileName == "a.png")
        #expect(items[0].host == "Imgur")
        #expect(Calendar.current.component(.year, from: items[0].date) == 2015)
        #expect(items[1].fileName == "b.png")
    }

    @Test func appendAllImportsInOneBatch() {
        withStore { store in
            let imported = store.appendAll([makeItem(fileName: "a.png"), makeItem(fileName: "b.png")])
            #expect(imported == 2)
            #expect(store.count() == 2)
        }
    }

    @Test func statsReportGroupsAndCounts() {
        var image = HistoryItem()
        image.fileName = "shot.png"
        image.type = "Image"
        image.host = "Imgur"
        image.tags = ["ProcessName": "Safari"]
        var text = HistoryItem()
        text.fileName = "note.txt"
        text.type = "Text"

        let report = HistoryStats.report([image, image, text])
        #expect(report.contains("Total: 3"))
        #expect(report.contains("Image: 2 (67%)"))
        #expect(report.contains("Text: 1 (33%)"))
        #expect(report.contains("[2] png"))
        #expect(report.contains("[2] Imgur"))
        #expect(report.contains("[1] (empty)"))
        #expect(report.contains("[2] Safari"))
    }

    /// Guard against drift from the upstream v21 SQLite writer
    /// (ShareX.HistoryLib/Managers/HistoryManagerSQLite.cs, verified 2026-07):
    /// same table, column set/order and Id primary key.
    @Test func schemaMatchesUpstreamV21Writer() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareXTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("History.db")
        let store = HistoryStore(url: url)
        store.append(makeItem(fileName: "schema.png"))

        var db: OpaquePointer?
        try #require(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(db, "PRAGMA table_info(History);", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }

        var columns: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            columns.append(String(cString: sqlite3_column_text(statement, 1)))
        }
        #expect(columns == ["Id", "FileName", "FilePath", "DateTime", "Type", "Host",
                            "URL", "ThumbnailURL", "DeletionURL", "ShortenedURL", "Tags"])
    }

    @Test func importsFolderOfMediaFiles() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShareXTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("sub"), withIntermediateDirectories: true)
        for name in ["a.png", "b.jpg", "sub/c.mp4", "notes.txt", ".hidden.png"] {
            try Data([0]).write(to: folder.appendingPathComponent(name))
        }

        let items = HistoryImport.items(fromFolder: folder)
        let names = Set(items.map(\.fileName))
        // media only, recursive, hidden skipped
        #expect(names == ["a.png", "b.jpg", "c.mp4"])
        #expect(items.first { $0.fileName == "a.png" }?.type == "Image")
        #expect(items.first { $0.fileName == "c.mp4" }?.type == "File")
        #expect(items.allSatisfy { $0.host == "File" })
    }

    @Test func parsesCSharpRoundTripDates() {
        // C# DateTime.ToString("o") without timezone (Unspecified kind)
        #expect(HistoryDate.date(from: "2015-08-30T12:36:00.0000000") != nil)
        // with offset
        #expect(HistoryDate.date(from: "2015-08-30T12:36:00.0000000+02:00") != nil)
        // our own writer round-trips
        let now = Date()
        let parsed = HistoryDate.date(from: HistoryDate.string(from: now))
        #expect(parsed != nil)
        #expect(abs(parsed!.timeIntervalSince(now)) < 0.001)
    }
}
