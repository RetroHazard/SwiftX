// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Contains code derived from ShareX, Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Swift port of ShareX.HelpersLib/NameParser/NameParser.cs.
// Replacement order deliberately mirrors the C# implementation - several codes
// are substring-sensitive (%mon2 before %mon, %yy before %y, %wy/%w2 before %w,
// bare %i last among increment codes).

import Foundation

public enum NameParserType {
    case `default`
    case text // allows new line
    case fileName
    case filePath
    case url // percent-encodes
}

public final class NameParser {
    public let type: NameParserType
    public var maxNameLength = 0
    public var maxTitleLength = 0
    public var autoIncrementNumber = 0 // %i, %ia, %ib, %iAa, %ix
    public var imageWidth = 0 // %width
    public var imageHeight = 0 // %height
    public var windowText: String? // %t
    public var processName: String? // %pn
    public var customTimeZone: TimeZone?
    public var isPreviewMode = false
    /// Fixed date for deterministic tests; nil = now.
    public var date: Date?

    /// Set once at startup; parse errors (%rf bad path) outside preview mode
    /// report here so the app layer can notify the user.
    public nonisolated(unsafe) static var onError: (@Sendable (String) -> Void)?

    public init(_ type: NameParserType = .default) {
        self.type = type
    }

    public static func parse(_ type: NameParserType, _ pattern: String) -> String {
        NameParser(type).parse(pattern)
    }

    public func parse(_ pattern: String) -> String {
        guard !pattern.isEmpty else { return "" }

        var s = pattern

        if let windowText {
            var text = sanitizeInput(windowText)
            if maxTitleLength > 0 {
                text = String(text.prefix(maxTitleLength))
            }
            s = s.replacingOccurrences(of: "%t", with: text)
        }

        if let processName {
            s = s.replacingOccurrences(of: "%pn", with: sanitizeInput(processName))
        }

        s = s.replacingOccurrences(of: "%width", with: imageWidth > 0 ? String(imageWidth) : "")
        s = s.replacingOccurrences(of: "%height", with: imageHeight > 0 ? String(imageHeight) : "")

        let dt = date ?? Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = customTimeZone ?? .current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond, .weekday, .weekOfYear], from: dt)

        s = s.replacingOccurrences(of: "%mon2", with: monthName(c.month!, english: true))
        s = s.replacingOccurrences(of: "%mon", with: monthName(c.month!, english: false))
        s = s.replacingOccurrences(of: "%yy", with: padZeroes(String(c.year! % 100), 2))
        s = s.replacingOccurrences(of: "%y", with: String(c.year!))
        s = s.replacingOccurrences(of: "%mo", with: padZeroes(String(c.month!), 2))
        s = s.replacingOccurrences(of: "%d", with: padZeroes(String(c.day!), 2))

        let hour24 = c.hour!
        let hour: String
        if s.contains("%pm") {
            let h12 = hour24 % 12 == 0 ? 12 : hour24 % 12
            hour = padZeroes(String(h12), 2)
        } else {
            hour = padZeroes(String(hour24), 2)
        }

        s = s.replacingOccurrences(of: "%h", with: hour)
        s = s.replacingOccurrences(of: "%mi", with: padZeroes(String(c.minute!), 2))
        s = s.replacingOccurrences(of: "%s", with: padZeroes(String(c.second!), 2))
        s = s.replacingOccurrences(of: "%ms", with: padZeroes(String(c.nanosecond! / 1_000_000), 3))
        s = s.replacingOccurrences(of: "%wy", with: String(c.weekOfYear!))
        s = s.replacingOccurrences(of: "%w2", with: weekdayName(c.weekday!, english: true))
        s = s.replacingOccurrences(of: "%w", with: weekdayName(c.weekday!, english: false))
        s = s.replacingOccurrences(of: "%pm", with: hour24 >= 12 ? "PM" : "AM")

        s = s.replacingOccurrences(of: "%unix", with: String(Int(dt.timeIntervalSince1970)))

        // Matches C#: any "%i" substring triggers the increment (including %ix, %ia, ...).
        if s.contains("%i") {
            autoIncrementNumber += 1
            let n = autoIncrementNumber

            // Custom base: %ib{base,pad} lowercase-first alphabet, %iB{base,pad} uppercase-first
            for (entry, values) in entriesWithValues(in: s, entry: "%ib", elements: 2) where values[0] >= 2 {
                s = s.replacingOccurrences(of: entry, with: padZeroes(toBase(n, base: values[0], alphabet: Chars.alphanumericInverse), values[1]))
            }
            for (entry, values) in entriesWithValues(in: s, entry: "%iB", elements: 2) where values[0] >= 2 {
                s = s.replacingOccurrences(of: entry, with: padZeroes(toBase(n, base: values[0], alphabet: Chars.alphanumeric), values[1]))
            }

            // Alphanumeric dual case (base 62)
            for (entry, values) in entriesWithValues(in: s, entry: "%iAa", elements: 1) {
                s = s.replacingOccurrences(of: entry, with: padZeroes(toBase(n, base: 62, alphabet: Chars.alphanumeric), values[0]))
            }
            s = s.replacingOccurrences(of: "%iAa", with: toBase(n, base: 62, alphabet: Chars.alphanumeric))
            for (entry, values) in entriesWithValues(in: s, entry: "%iaA", elements: 1) {
                s = s.replacingOccurrences(of: entry, with: padZeroes(toBase(n, base: 62, alphabet: Chars.alphanumericInverse), values[0]))
            }
            s = s.replacingOccurrences(of: "%iaA", with: toBase(n, base: 62, alphabet: Chars.alphanumericInverse))

            // Alphanumeric single case (base 36)
            for (entry, values) in entriesWithValues(in: s, entry: "%ia", elements: 1) {
                s = s.replacingOccurrences(of: entry, with: padZeroes(toBase(n, base: 36, alphabet: Chars.alphanumeric), values[0]).lowercased())
            }
            s = s.replacingOccurrences(of: "%ia", with: toBase(n, base: 36, alphabet: Chars.alphanumeric).lowercased())
            for (entry, values) in entriesWithValues(in: s, entry: "%iA", elements: 1) {
                s = s.replacingOccurrences(of: entry, with: padZeroes(toBase(n, base: 36, alphabet: Chars.alphanumeric), values[0]).uppercased())
            }
            s = s.replacingOccurrences(of: "%iA", with: toBase(n, base: 36, alphabet: Chars.alphanumeric).uppercased())

            // Hexadecimal
            for (entry, values) in entriesWithValues(in: s, entry: "%ix", elements: 1) {
                s = s.replacingOccurrences(of: entry, with: padZeroes(String(n, radix: 16, uppercase: false), values[0]))
            }
            s = s.replacingOccurrences(of: "%ix", with: String(n, radix: 16, uppercase: false))
            for (entry, values) in entriesWithValues(in: s, entry: "%iX", elements: 1) {
                s = s.replacingOccurrences(of: entry, with: padZeroes(String(n, radix: 16, uppercase: true), values[0]))
            }
            s = s.replacingOccurrences(of: "%iX", with: String(n, radix: 16, uppercase: true))

            // Number (base 10) - bare %i last so it can't eat the other codes
            for (entry, values) in entriesWithValues(in: s, entry: "%i", elements: 1) {
                s = s.replacingOccurrences(of: entry, with: padZeroes(String(n), values[0]))
            }
            s = s.replacingOccurrences(of: "%i", with: String(n))
        }

        s = s.replacingOccurrences(of: "%un", with: NSUserName())
        // C# maps %uln to Environment.UserDomainName, which is the machine name off-domain
        s = s.replacingOccurrences(of: "%uln", with: Self.computerName)
        s = s.replacingOccurrences(of: "%cn", with: Self.computerName)

        if type == .text {
            s = s.replacingOccurrences(of: "%n", with: "\n")
        }

        s = replaceEachOccurrence(in: s, of: "%radjective") { WordLists.adjectives.randomElement()?.capitalized ?? "" }
        s = replaceEachOccurrence(in: s, of: "%ranimal") { WordLists.animals.randomElement()?.capitalized ?? "" }

        for (entry, path) in entriesWithArgument(in: s, entry: "%rf") {
            s = replaceEachOccurrence(in: s, of: entry) { [isPreviewMode] in
                if let line = randomLineFromFile(path) {
                    return line
                }
                let message = "Valid text file path is required."
                if isPreviewMode { return message }
                // ponytail: C# throws and fails the whole task; we report and substitute ""
                Self.onError?("%rf \(path): \(message)")
                return ""
            }
        }

        for (entry, values) in entriesWithValues(in: s, entry: "%rna", elements: 1) {
            s = replaceEachOccurrence(in: s, of: entry) { randomString(Chars.base56, count: values[0]) }
        }
        for (entry, values) in entriesWithValues(in: s, entry: "%rn", elements: 1) {
            s = replaceEachOccurrence(in: s, of: entry) { randomString(Chars.numbers, count: values[0]) }
        }
        for (entry, values) in entriesWithValues(in: s, entry: "%ra", elements: 1) {
            s = replaceEachOccurrence(in: s, of: entry) { randomString(Chars.alphanumeric, count: values[0]) }
        }
        for (entry, values) in entriesWithValues(in: s, entry: "%rx", elements: 1) {
            s = replaceEachOccurrence(in: s, of: entry) { randomString(Chars.hexadecimal, count: values[0]).lowercased() }
        }
        for (entry, values) in entriesWithValues(in: s, entry: "%rX", elements: 1) {
            s = replaceEachOccurrence(in: s, of: entry) { randomString(Chars.hexadecimal, count: values[0]).uppercased() }
        }
        for (entry, values) in entriesWithValues(in: s, entry: "%remoji", elements: 1) {
            s = replaceEachOccurrence(in: s, of: entry) { randomString(fromArray: Emoji.emojis, count: values[0]) }
        }

        s = replaceEachOccurrence(in: s, of: "%rna") { randomString(Chars.base56, count: 1) }
        s = replaceEachOccurrence(in: s, of: "%rn") { randomString(Chars.numbers, count: 1) }
        s = replaceEachOccurrence(in: s, of: "%ra") { randomString(Chars.alphanumeric, count: 1) }
        s = replaceEachOccurrence(in: s, of: "%rx") { randomString(Chars.hexadecimal, count: 1).lowercased() }
        s = replaceEachOccurrence(in: s, of: "%rX") { randomString(Chars.hexadecimal, count: 1).uppercased() }
        s = replaceEachOccurrence(in: s, of: "%guid") { UUID().uuidString.lowercased() }
        s = replaceEachOccurrence(in: s, of: "%GUID") { UUID().uuidString.uppercased() }
        s = replaceEachOccurrence(in: s, of: "%remoji") { randomString(fromArray: Emoji.emojis, count: 1) }

        switch type {
        case .fileName:
            s = Sanitize.fileName(s)
        case .filePath:
            s = Sanitize.path(s)
        case .url:
            s = Sanitize.url(s)
        case .default, .text:
            break
        }

        if maxNameLength > 0 {
            s = String(s.prefix(maxNameLength))
        }

        return s
    }

    // MARK: - Input sanitizing

    private func sanitizeInput(_ input: String) -> String {
        var result = input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "_")
        if type == .fileName || type == .filePath {
            result = Sanitize.fileName(result)
        }
        return result
    }

    // MARK: - Entry argument parsing (%code{arg1,arg2})

    private func entriesWithArguments(in text: String, entry: String, elements: Int) -> [(String, [String])] {
        var results: [(String, [String])] = []
        let open = entry + "{"
        var searchStart = text.startIndex
        while let openRange = text.range(of: open, range: searchStart..<text.endIndex) {
            guard let closeRange = text.range(of: "}", range: openRange.upperBound..<text.endIndex) else { break }
            var parts = text[openRange.upperBound..<closeRange.lowerBound].components(separatedBy: ",")
            while parts.count < elements {
                parts.append("")
            }
            results.append((String(text[openRange.lowerBound..<closeRange.upperBound]), parts))
            searchStart = closeRange.upperBound
        }
        return results
    }

    private func entriesWithArgument(in text: String, entry: String) -> [(String, String)] {
        entriesWithArguments(in: text, entry: entry, elements: 1).map { ($0.0, $0.1[0]) }
    }

    private func entriesWithValues(in text: String, entry: String, elements: Int) -> [(String, [Int])] {
        entriesWithArguments(in: text, entry: entry, elements: elements).map { entry, parts in
            (entry, parts.map { Int($0) ?? 0 })
        }
    }

    // MARK: - Helpers

    private func replaceEachOccurrence(in text: String, of target: String, with generator: () -> String) -> String {
        var result = text
        while let range = result.range(of: target) {
            result.replaceSubrange(range, with: generator())
        }
        return result
    }

    private func padZeroes(_ value: String, _ digits: Int) -> String {
        value.count >= digits ? value : String(repeating: "0", count: digits - value.count) + value
    }

    private func toBase(_ value: Int, base: Int, alphabet: String) -> String {
        let chars = Array(alphabet)
        guard base >= 2, base <= chars.count else { return "" }
        guard value > 0 else { return String(chars[0]) }
        var n = value
        var result = ""
        while n > 0 {
            result = String(chars[n % base]) + result
            n /= base
        }
        return result
    }

    private func randomString(_ alphabet: String, count: Int) -> String {
        guard count > 0 else { return "" }
        return String((0..<count).compactMap { _ in alphabet.randomElement() })
    }

    private func randomString(fromArray array: [String], count: Int) -> String {
        guard count > 0 else { return "" }
        return (0..<count).compactMap { _ in array.randomElement() }.joined()
    }

    private func randomLineFromFile(_ path: String) -> String? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.randomElement()
    }

    private func monthName(_ month: Int, english: Bool) -> String {
        let formatter = DateFormatter()
        if english {
            formatter.locale = Locale(identifier: "en_US_POSIX")
        }
        return formatter.monthSymbols[month - 1]
    }

    private func weekdayName(_ weekday: Int, english: Bool) -> String {
        let formatter = DateFormatter()
        if english {
            formatter.locale = Locale(identifier: "en_US_POSIX")
        }
        return formatter.weekdaySymbols[weekday - 1]
    }

    private static let computerName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
}

// MARK: - Character sets (mirrors ShareX.HelpersLib/Helpers/Helpers.cs)

enum Chars {
    static let numbers = "0123456789"
    static let alphabetCapital = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    static let alphabet = "abcdefghijklmnopqrstuvwxyz"
    static let alphanumeric = numbers + alphabetCapital + alphabet
    static let alphanumericInverse = numbers + alphabet + alphabetCapital
    static let hexadecimal = numbers + "ABCDEF"
    static let base56 = "23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz"
}

private extension String {
    init(_ value: Int, radix: Int, uppercase: Bool) {
        let s = String(value, radix: radix)
        self = uppercase ? s.uppercased() : s
    }
}

// MARK: - Word list resources (same .txt files as ShareX.HelpersLib/Resources)

enum WordLists {
    static let adjectives = load("adjectives")
    static let animals = load("animals")

    private static func load(_ name: String) -> [String] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "txt"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return content.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }
}

// Full port of C# Emoji.cs (%remoji source list).
enum Emoji {
    static let smileys: [String] = ["😀", "😁", "😂", "🤣", "😃", "😄", "😅", "😆", "😉", "😊", "😋", "😎", "😍", "😘", "🥰", "😗", "😙", "😚", "☺️", "🙂", "🤗", "🤩", "🤔", "🤨", "😐", "😑", "😶", "🙄", "😏", "😣", "😥", "😮", "🤐", "😯", "😪", "😫", "😴", "😌", "😛", "😜", "😝", "🤤", "😒", "😓", "😔", "😕", "🙃", "🤑", "😲", "☹️", "🙁", "😖", "😞", "😟", "😤", "😢", "😭", "😦", "😧", "😨", "😩", "🤯", "😬", "😰", "😱", "🥵", "🥶", "😳", "🤪", "😵", "😡", "😠", "🤬", "😷", "🤒", "🤕", "🤢", "🤮", "🤧", "😇", "🤠", "🤡", "🥳", "🥴", "🥺", "🤥", "🤫", "🤭", "🧐", "🤓", "😈", "👿", "👹", "👺", "💀", "👻", "👽", "🤖", "💩", "😺", "😸", "😹", "😻", "😼", "😽", "🙀", "😿", "😾"]
    static let animalsNature: [String] = ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🦝", "🐻", "🐼", "🦘", "🦡", "🐨", "🐯", "🦁", "🐮", "🐷", "🐽", "🐸", "🐵", "🙈", "🙉", "🙊", "🐒", "🐔", "🐧", "🐦", "🐤", "🐣", "🐥", "🦆", "🦢", "🦅", "🦉", "🦚", "🦜", "🦇", "🐺", "🐗", "🐴", "🦄", "🐝", "🐛", "🦋", "🐌", "🐚", "🐞", "🐜", "🦗", "🕷", "🕸", "🦂", "🦟", "🦠", "🐢", "🐍", "🦎", "🦖", "🦕", "🐙", "🦑", "🦐", "🦀", "🐡", "🐠", "🐟", "🐬", "🐳", "🐋", "🦈", "🐊", "🐅", "🐆", "🦓", "🦍", "🐘", "🦏", "🦛", "🐪", "🐫", "🦙", "🦒", "🐃", "🐂", "🐄", "🐎", "🐖", "🐏", "🐑", "🐐", "🦌", "🐕", "🐩", "🐈", "🐓", "🦃", "🕊", "🐇", "🐁", "🐀", "🐿", "🦔", "🐾", "🐉", "🐲", "🌵", "🎄", "🌲", "🌳", "🌴", "🌱", "🌿", "☘️", "🍀", "🎍", "🎋", "🍃", "🍂", "🍁", "🍄", "🌾", "💐", "🌷", "🌹", "🥀", "🌺", "🌸", "🌼", "🌻", "🌞", "🌝", "🌛", "🌜", "🌚", "🌕", "🌖", "🌗", "🌘", "🌑", "🌒", "🌓", "🌔", "🌙", "🌎", "🌍", "🌏", "💫", "⭐️", "🌟", "✨", "⚡️", "☄️", "💥", "🔥", "🌪", "🌈", "☀️", "🌤", "⛅️", "🌥", "☁️", "🌦", "🌧", "⛈", "🌩", "🌨", "❄️", "☃️", "⛄️", "🌬", "💨", "💧", "💦", "☔️", "☂️", "🌊", "🌫"]
    static let foodDrink: [String] = ["🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🍈", "🍒", "🍑", "🍍", "🥭", "🥥", "🥝", "🍅", "🍆", "🥑", "🥦", "🥒", "🥬", "🌶", "🌽", "🥕", "🥔", "🍠", "🥐", "🍞", "🥖", "🥨", "🥯", "🧀", "🥚", "🍳", "🥞", "🥓", "🥩", "🍗", "🍖", "🌭", "🍔", "🍟", "🍕", "🥪", "🥙", "🌮", "🌯", "🥗", "🥘", "🥫", "🍝", "🍜", "🍲", "🍛", "🍣", "🍱", "🥟", "🍤", "🍙", "🍚", "🍘", "🍥", "🥮", "🥠", "🍢", "🍡", "🍧", "🍨", "🍦", "🥧", "🍰", "🎂", "🍮", "🍭", "🍬", "🍫", "🍿", "🧂", "🍩", "🍪", "🌰", "🥜", "🍯", "🥛", "🍼", "☕️", "🍵", "🥤", "🍶", "🍺", "🍻", "🥂", "🍷", "🥃", "🍸", "🍹", "🍾", "🥄", "🍴", "🍽", "🥣", "🥡", "🥢"]
    static let travelPlaces: [String] = ["🚗", "🚕", "🚙", "🚌", "🚎", "🏎", "🚓", "🚑", "🚒", "🚐", "🚚", "🚛", "🚜", "🛴", "🚲", "🛵", "🏍", "🚨", "🚔", "🚍", "🚘", "🚖", "🚡", "🚠", "🚟", "🚃", "🚋", "🚞", "🚝", "🚄", "🚅", "🚈", "🚂", "🚆", "🚇", "🚊", "🚉", "✈️", "🛫", "🛬", "🛩", "💺", "🛰", "🚀", "🛸", "🚁", "🛶", "⛵️", "🚤", "🛥", "🛳", "⛴", "🚢", "⚓️", "⛽️", "🚧", "🚦", "🚥", "🚏", "🗺", "🗿", "🗽", "🗼", "🏰", "🏯", "🏟", "🎡", "🎢", "🎠", "⛲️", "⛱", "🏖", "🏝", "🏜", "🌋", "⛰", "🏔", "🗻", "🏕", "⛺️", "🏠", "🏡", "🏘", "🏚", "🏗", "🏭", "🏢", "🏬", "🏣", "🏤", "🏥", "🏦", "🏨", "🏪", "🏫", "🏩", "💒", "🏛", "⛪️", "🕌", "🕍", "🕋", "⛩", "🛤", "🛣", "🗾", "🎑", "🏞", "🌅", "🌄", "🌠", "🎇", "🎆", "🌇", "🌆", "🏙", "🌃", "🌌", "🌉", "🌁"]
    static let objects: [String] = ["⌚️", "📱", "📲", "💻", "⌨️", "🖥", "🖨", "🖱", "🖲", "🕹", "🗜", "💽", "💾", "💿", "📀", "📼", "📷", "📸", "📹", "🎥", "📽", "🎞", "📞", "☎️", "📟", "📠", "📺", "📻", "🎙", "🎚", "🎛", "⏱", "⏲", "⏰", "🕰", "⌛️", "⏳", "📡", "🔋", "🔌", "💡", "🔦", "🕯", "🗑", "🛢", "💸", "💵", "💴", "💶", "💷", "💰", "💳", "🧾", "💎", "⚖️", "🔧", "🔨", "⚒", "🛠", "⛏", "🔩", "⚙️", "⛓", "🔫", "💣", "🔪", "🗡", "⚔️", "🛡", "🚬", "⚰️", "⚱️", "🏺", "🧭", "🧱", "🔮", "🧿", "🧸", "📿", "💈", "⚗️", "🔭", "🧰", "🧲", "🧪", "🧫", "🧬", "🧯", "🔬", "🕳", "💊", "💉", "🌡", "🚽", "🚰", "🚿", "🛁", "🛀", "🛀🏻", "🛀🏼", "🛀🏽", "🛀🏾", "🛀🏿", "🧴", "🧵", "🧶", "🧷", "🧹", "🧺", "🧻", "🧼", "🧽", "🛎", "🔑", "🗝", "🚪", "🛋", "🛏", "🛌", "🖼", "🛍", "🧳", "🛒", "🎁", "🎈", "🎏", "🎀", "🎊", "🎉", "🧨", "🎎", "🏮", "🎐", "🧧", "✉️", "📩", "📨", "📧", "💌", "📥", "📤", "📦", "🏷", "📪", "📫", "📬", "📭", "📮", "📯", "📜", "📃", "📄", "📑", "📊", "📈", "📉", "🗒", "🗓", "📆", "📅", "📇", "🗃", "🗳", "🗄", "📋", "📁", "📂", "🗂", "🗞", "📰", "📓", "📔", "📒", "📕", "📗", "📘", "📙", "📚", "📖", "🔖", "🔗", "📎", "🖇", "📐", "📏", "📌", "📍", "✂️", "🖊", "🖋", "✒️", "🖌", "🖍", "📝", "✏️", "🔍", "🔎", /*"🔏", "🔐", "🔒", "🔓"*/]
    static let emojis = smileys + animalsNature + foodDrink + travelPlaces + objects
}

// MARK: - Output sanitizing

enum Sanitize {
    // Windows-invalid chars removed too, so generated names stay portable across sync/upload targets
    private static let invalidFileNameChars: Set<Character> = ["\\", "/", ":", "*", "?", "\"", "<", ">", "|"]

    static func fileName(_ name: String) -> String {
        String(name.filter { !invalidFileNameChars.contains($0) && !$0.isControl })
            .trimmingCharacters(in: .whitespaces)
    }

    static func path(_ path: String) -> String {
        path.components(separatedBy: "/").map { fileName($0) }.joined(separator: "/")
    }

    static func url(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert(charactersIn: ":?#[]@!$&'()*+,;=%")
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
    }

    private static let controlCharacters = CharacterSet.controlCharacters
}

private extension Character {
    var isControl: Bool {
        unicodeScalars.allSatisfy { CharacterSet.controlCharacters.contains($0) }
    }
}
