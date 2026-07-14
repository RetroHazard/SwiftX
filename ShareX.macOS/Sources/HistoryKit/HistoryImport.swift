// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Imports Windows ShareX History.json / History.xml (the pre-SQLite formats,
// mirroring HistoryManagerJSON.cs / HistoryManagerXML.cs). Both files are
// element streams without a document root; we wrap before parsing, exactly
// like the C# loaders do.

import Foundation

public enum HistoryImport {
    public static func items(fromFile url: URL) throws -> [HistoryItem] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return url.pathExtension.lowercased() == "xml" ? items(fromXML: text) : items(fromJSON: text)
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
