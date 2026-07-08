// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
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
