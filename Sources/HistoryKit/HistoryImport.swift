// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE
//
// Imports Windows ShareX History.json / History.xml (the pre-SQLite formats,
// mirroring HistoryManagerJSON.cs / HistoryManagerXML.cs). Both files are
// element streams without a document root; we wrap before parsing, exactly
// like the C# loaders do. Modern (v21) History.db files use the same SQLite
// schema as SwiftX's own store and import row-by-row.

import Foundation
import SQLite3

public enum HistoryImport {
    public static func items(fromFile url: URL) throws -> [HistoryItem] {
        if url.pathExtension.lowercased() == "db" {
            return items(fromSQLiteDatabase: url)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return url.pathExtension.lowercased() == "xml" ? items(fromXML: text) : items(fromJSON: text)
    }

    /// Windows ShareX v21+ History.db (same History table SwiftX writes).
    /// Read-only open so a live/locked source file can't be corrupted.
    public static func items(fromSQLiteDatabase url: URL) -> [HistoryItem] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT FileName, FilePath, DateTime, Type, Host, URL, ThumbnailURL, DeletionURL, ShortenedURL, Tags
        FROM History ORDER BY Id ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        func column(_ index: Int32) -> String {
            guard let text = sqlite3_column_text(statement, index) else { return "" }
            return String(cString: text)
        }

        var items: [HistoryItem] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var item = HistoryItem()
            item.fileName = column(0)
            item.filePath = column(1)
            item.date = HistoryDate.date(from: column(2)) ?? .distantPast
            item.type = column(3)
            item.host = column(4)
            item.url = column(5)
            item.thumbnailURL = column(6)
            item.deletionURL = column(7)
            item.shortenedURL = column(8)
            if let data = column(9).data(using: .utf8),
               let tags = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                item.tags = tags.mapValues { $0 as? String ?? "" }
            }
            items.append(item)
        }
        return items
    }

    /// History.json is `{...},\r\n{...}` — comma-separated objects, no brackets.
    public static func items(fromJSON text: String) -> [HistoryItem] {
        guard let data = ("[" + text + "]").data(using: .utf8),
              let objects = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return [] }

        return objects.map { object in
            var item = HistoryItem()
            item.fileName = object["FileName"] as? String ?? ""
            item.filePath = object["FilePath"] as? String ?? ""
            item.date = (object["DateTime"] as? String).flatMap(HistoryDate.date(from:)) ?? .distantPast
            item.type = object["Type"] as? String ?? "Image"
            item.host = object["Host"] as? String ?? ""
            item.url = object["URL"] as? String ?? ""
            item.thumbnailURL = object["ThumbnailURL"] as? String ?? ""
            item.deletionURL = object["DeletionURL"] as? String ?? ""
            item.shortenedURL = object["ShortenedURL"] as? String ?? ""
            if let tags = object["Tags"] as? [String: Any] {
                // C# writes Favorite with a null value; presence is what matters
                item.tags = tags.mapValues { $0 as? String ?? "" }
            }
            return item
        }
    }

    /// Upstream v21 "import folder": ingest a directory of media files as
    /// history entries. Recursive, hidden files skipped; images get Type
    /// "Image", audio/video get "File" (matching what captures/recordings
    /// record); dates come from the files' creation dates.
    public static func items(fromFolder folder: URL) -> [HistoryItem] {
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic"]
        let mediaExtensions: Set<String> = ["mp4", "mov", "webm", "apng", "mkv", "avi", "m4v", "mp3", "m4a", "wav"]

        let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey, .creationDateKey],
            options: [.skipsHiddenFiles])
        var items: [HistoryItem] = []
        while let file = enumerator?.nextObject() as? URL {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .creationDateKey])
            guard values?.isRegularFile == true else { continue }
            let ext = file.pathExtension.lowercased()
            let isImage = imageExtensions.contains(ext)
            guard isImage || mediaExtensions.contains(ext) else { continue }

            var item = HistoryItem()
            item.fileName = file.lastPathComponent
            item.filePath = file.path
            item.date = values?.creationDate ?? .distantPast
            item.type = isImage ? "Image" : "File"
            item.host = "File"
            items.append(item)
        }
        // stable order for batch inserts: oldest first so "recent" stays sane
        return items.sorted { $0.date < $1.date }
    }

    /// History.xml is a stream of root-level <HistoryItem> fragments.
    public static func items(fromXML text: String) -> [HistoryItem] {
        guard let data = ("<Root>" + text + "</Root>").data(using: .utf8) else { return [] }
        let parser = XMLParser(data: data)
        let collector = XMLHistoryCollector()
        parser.delegate = collector
        parser.parse()
        return collector.items
    }
}

private final class XMLHistoryCollector: NSObject, XMLParserDelegate {
    var items: [HistoryItem] = []
    private var current: HistoryItem?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        if name == "HistoryItem" { current = HistoryItem() }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard current != nil else { return }
        switch name {
        case "HistoryItem":
            items.append(current!)
            current = nil
        case "Filename": current?.fileName = text
        case "Filepath": current?.filePath = text
        case "DateTimeUtc": current?.date = HistoryDate.date(from: text) ?? .distantPast
        case "Type": current?.type = text
        case "Host": current?.host = text
        case "URL": current?.url = text
        case "ThumbnailURL": current?.thumbnailURL = text
        case "DeletionURL": current?.deletionURL = text
        case "ShortenedURL": current?.shortenedURL = text
        default: break
        }
    }
}
