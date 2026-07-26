// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Text stats report, same sections as ShareX.HistoryLib/HistoryHelpers.OutputStats:
// totals, types, yearly usage, file extensions, hosts, process names.

import Foundation

public enum HistoryStats {
    public static func report(_ items: [HistoryItem]) -> String {
        let empty = "(empty)"
        var lines: [String] = []

        lines.append("History item counts:")
        lines.append("Total: \(items.count)")
        lines.append(contentsOf: percentGroups(items) { $0.type })

        lines.append("")
        lines.append("Yearly usages:")
        let calendar = Calendar.current
        lines.append(contentsOf: percentGroups(items, sortedByKeyDescending: true) {
            String(calendar.component(.year, from: $0.date))
        })

        lines.append("")
        lines.append("File extensions:")
        // C# skips names ending in ")" — text uploads get names like "(clipboard)"
        let extensions = items.filter { !$0.fileName.isEmpty && !$0.fileName.hasSuffix(")") }
            .map { ($0.fileName as NSString).pathExtension }
        lines.append(contentsOf: countGroups(extensions.map { $0.isEmpty ? empty : $0 }))

        lines.append("")
        lines.append("Hosts:")
        lines.append(contentsOf: countGroups(items.map { $0.host.isEmpty ? empty : $0.host }))

        lines.append("")
        lines.append("Process names:")
        lines.append(contentsOf: countGroups(items.map { item in
            let name = item.tags["ProcessName"] ?? ""
            return name.isEmpty ? empty : name
        }))

        return lines.joined(separator: "\n")
    }

    /// "Image: 12 (60%)" rows, most frequent first.
    private static func percentGroups(_ items: [HistoryItem], sortedByKeyDescending: Bool = false,
                                      by key: (HistoryItem) -> String) -> [String] {
        guard !items.isEmpty else { return [] }
        let groups = Dictionary(grouping: items, by: key)
        let sorted = sortedByKeyDescending
            ? groups.sorted { $0.key > $1.key }
            : groups.sorted { $0.value.count > $1.value.count }
        return sorted.map { key, members in
            let percent = (Double(members.count) / Double(items.count) * 100).rounded()
            return "\(key): \(members.count) (\(Int(percent))%)"
        }
    }

    /// "[12] png" rows, most frequent first.
    private static func countGroups(_ keys: [String]) -> [String] {
        Dictionary(grouping: keys, by: { $0 })
            .sorted { $0.value.count > $1.value.count }
            .map { "[\($0.value.count)] \($0.key)" }
    }
}
