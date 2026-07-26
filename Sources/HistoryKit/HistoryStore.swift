// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// SQLite history store. Table name, columns, ISO-8601 date strings and
// JSON-encoded Tags mirror ShareX.HistoryLib/HistoryManagerSQLite.cs, so a
// History.db from Windows ShareX opens unchanged.

import Foundation
import SQLite3
import SharedKit

public struct HistoryItem: Identifiable, Equatable {
    public var id: Int64 = 0
    public var fileName = ""
    public var filePath = ""
    public var date = Date()
    public var type = "Image"
    public var host = ""
    public var url = ""
    public var thumbnailURL = ""
    public var deletionURL = ""
    public var shortenedURL = ""
    public var tags: [String: String] = [:]

    public init() {}

    /// Same convention as Windows ShareX: favorite = presence of a "Favorite" tag.
    public var isFavorite: Bool { tags["Favorite"] != nil }
}

// ponytail: everything runs on the main actor - appends are single-row and reads
// are LIMITed; move to an actor with a background queue if lists ever feel slow
@MainActor
public final class HistoryStore {
    public static let shared = HistoryStore(url: SettingsPaths.root.appendingPathComponent("History.db"))
    public static let changedNotification = Notification.Name("SwiftXHistoryChanged")

    private var db: OpaquePointer?
    private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            AppLog.history.error("Cannot open \(url.path, privacy: .public)")
            db = nil
            return
        }
        // upstream v21 HistoryManagerSQLite sets this; matters if a second
        // writer (e.g. a migration tool) ever holds the file
        execute("PRAGMA busy_timeout = 5000;")
        execute("""
        CREATE TABLE IF NOT EXISTS History (
            Id INTEGER PRIMARY KEY AUTOINCREMENT,
            FileName TEXT,
            FilePath TEXT,
            DateTime TEXT,
            Type TEXT,
            Host TEXT,
            URL TEXT,
            ThumbnailURL TEXT,
            DeletionURL TEXT,
            ShortenedURL TEXT,
            Tags TEXT
        );
        """)
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Writes

    @discardableResult
    public func append(_ item: HistoryItem) -> HistoryItem {
        let inserted = insert(item)
        if inserted.id > 0 {
            NotificationCenter.default.post(name: Self.changedNotification, object: nil)
        }
        return inserted
    }

    /// Batch import (Windows History.json/xml) in one transaction, one notification.
    @discardableResult
    public func appendAll(_ items: [HistoryItem]) -> Int {
        execute("BEGIN;")
        let count = items.filter { insert($0).id > 0 }.count
        execute("COMMIT;")
        if count > 0 {
            NotificationCenter.default.post(name: Self.changedNotification, object: nil)
        }
        return count
    }

    private func insert(_ item: HistoryItem) -> HistoryItem {
        var statement: OpaquePointer?
        let sql = """
        INSERT INTO History (FileName, FilePath, DateTime, Type, Host, URL, ThumbnailURL, DeletionURL, ShortenedURL, Tags)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return item }
        defer { sqlite3_finalize(statement) }

        let tagsJSON = (try? JSONSerialization.data(withJSONObject: item.tags)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let values = [item.fileName, item.filePath, HistoryDate.string(from: item.date), item.type,
                      item.host, item.url, item.thumbnailURL, item.deletionURL, item.shortenedURL, tagsJSON]
        for (index, value) in values.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { return item }

        var inserted = item
        inserted.id = sqlite3_last_insert_rowid(db)
        return inserted
    }

    /// After an upload completes, fill in the URLs on the newest row for that file.
    public func updateUploadURLs(filePath: String, host: String, url: String,
                                 thumbnailURL: String = "", deletionURL: String = "", shortenedURL: String = "") {
        var statement: OpaquePointer?
        let sql = """
        UPDATE History SET Host = ?, URL = ?, ThumbnailURL = ?, DeletionURL = ?, ShortenedURL = ?
        WHERE Id = (SELECT Id FROM History WHERE FilePath = ? ORDER BY Id DESC LIMIT 1);
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        for (index, value) in [host, url, thumbnailURL, deletionURL, shortenedURL, filePath].enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }
        if sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(db) > 0 {
            NotificationCenter.default.post(name: Self.changedNotification, object: nil)
        }
    }

    /// Sets or clears the "Favorite" tag on a row (read-modify-write of the Tags JSON).
    public func setFavorite(id: Int64, _ favorite: Bool) {
        guard let item = recent(limit: 1, matchingId: id).first else { return }
        var tags = item.tags
        if favorite {
            tags["Favorite"] = "true"
        } else {
            tags.removeValue(forKey: "Favorite")
        }
        let tagsJSON = (try? JSONSerialization.data(withJSONObject: tags)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE History SET Tags = ? WHERE Id = ?;", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, tagsJSON, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 2, id)
        if sqlite3_step(statement) == SQLITE_DONE {
            NotificationCenter.default.post(name: Self.changedNotification, object: nil)
        }
    }

    // MARK: - Reads

    public func recent(limit: Int = 200, search: String = "", favoritesOnly: Bool = false,
                       from: Date? = nil, matchingId: Int64? = nil) -> [HistoryItem] {
        var statement: OpaquePointer?
        var conditions: [String] = []
        let trimmed = search.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            // Tags LIKE covers C#'s SearchInTags (window title, process name);
            // matching the raw JSON also hits tag keys, which is fine
            conditions.append("(FileName LIKE ? OR URL LIKE ? OR Host LIKE ? OR Tags LIKE ?)")
        }
        if favoritesOnly {
            conditions.append("Tags LIKE '%\"Favorite\"%'")
        }
        if from != nil {
            // our rows use UTC ISO-8601, which sorts lexicographically; imported
            // C# rows without timezone suffix may sort slightly off - acceptable
            conditions.append("DateTime >= ?")
        }
        if matchingId != nil {
            conditions.append("Id = ?")
        }

        var sql = "SELECT Id, FileName, FilePath, DateTime, Type, Host, URL, ThumbnailURL, DeletionURL, ShortenedURL, Tags FROM History"
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }
        sql += " ORDER BY Id DESC LIMIT ?;"

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var bindIndex: Int32 = 1
        if !trimmed.isEmpty {
            let pattern = "%\(trimmed)%"
            for _ in 0..<4 {
                sqlite3_bind_text(statement, bindIndex, pattern, -1, SQLITE_TRANSIENT)
                bindIndex += 1
            }
        }
        if let from {
            sqlite3_bind_text(statement, bindIndex, HistoryDate.string(from: from), -1, SQLITE_TRANSIENT)
            bindIndex += 1
        }
        if let matchingId {
            sqlite3_bind_int64(statement, bindIndex, matchingId)
            bindIndex += 1
        }
        sqlite3_bind_int(statement, bindIndex, Int32(limit))

        var items: [HistoryItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var item = HistoryItem()
            item.id = sqlite3_column_int64(statement, 0)
            item.fileName = column(statement, 1)
            item.filePath = column(statement, 2)
            item.date = HistoryDate.date(from: column(statement, 3)) ?? .distantPast
            item.type = column(statement, 4)
            item.host = column(statement, 5)
            item.url = column(statement, 6)
            item.thumbnailURL = column(statement, 7)
            item.deletionURL = column(statement, 8)
            item.shortenedURL = column(statement, 9)
            if let data = column(statement, 10).data(using: .utf8),
               let tags = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // C# writes Favorite with a null value; keep the key, drop the null
                item.tags = tags.mapValues { $0 as? String ?? "" }
            }
            items.append(item)
        }
        return items
    }

    public func count() -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM History;", -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
    }

    // MARK: - Internals

    private func execute(_ sql: String) {
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK, let errorMessage {
            AppLog.history.error("\(String(cString: errorMessage), privacy: .public)")
            sqlite3_free(errorMessage)
        }
    }

    private func column(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let text = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: text)
    }
}

/// C# writes DateTime.ToString("o"); parse tolerantly, write ISO-8601 with
/// fractional seconds so both sides can read each other's rows.
enum HistoryDate {
    private static let writer: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let readers: [DateFormatter] = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSXXXXX", // C# "o" with offset
        "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS",      // C# "o" unspecified kind
        "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
        "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        "yyyy-MM-dd'T'HH:mm:ss"
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }

    static func string(from date: Date) -> String {
        writer.string(from: date)
    }

    static func date(from string: String) -> Date? {
        if let date = writer.date(from: string) { return date }
        for reader in readers {
            if let date = reader.date(from: string) { return date }
        }
        return nil
    }
}
