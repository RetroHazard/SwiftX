// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import Testing
@testable import SharedKit

struct NameParserTests {
    private let utc = TimeZone(identifier: "UTC")!

    @Test func remojiDrawsFromFullCSharpList() {
        // Smileys+AnimalsNature+FoodDrink+TravelPlaces+Objects; C# comments out the last 4 lock emojis
        #expect(Emoji.emojis.count == 705)
        let result = NameParser(.default).parse("%remoji")
        #expect(Emoji.emojis.contains(result))
    }

    @Test func rfWithBadPathReportsErrorAndSubstitutesEmpty() {
        nonisolated(unsafe) var reported: String?
        NameParser.onError = { reported = $0 }
        defer { NameParser.onError = nil }
        #expect(NameParser(.default).parse("a%rf{/no/such/file.txt}b") == "ab")
        #expect(reported?.contains("Valid text file path is required.") == true)

        let preview = NameParser(.default)
        preview.isPreviewMode = true
        #expect(preview.parse("%rf{/no/such/file.txt}") == "Valid text file path is required.")
    }

    private func makeParser(_ type: NameParserType = .default, hour: Int = 9) -> NameParser {
        let parser = NameParser(type)
        parser.customTimeZone = utc
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        // Thursday 2024-03-07, ms=500 (exactly representable as a Double)
        parser.date = calendar.date(from: DateComponents(
            year: 2024, month: 3, day: 7, hour: hour, minute: 5, second: 3, nanosecond: 500_000_000
        ))!
        return parser
    }

    // MARK: Date and time codes

    @Test func dateCodes() {
        let parser = makeParser()
        #expect(parser.parse("%y-%mo-%d_%h-%mi-%s") == "2024-03-07_09-05-03")
        #expect(parser.parse("%yy") == "24")
        #expect(parser.parse("%ms") == "500")
        #expect(parser.parse("%mon2") == "March")
        #expect(parser.parse("%w2") == "Thursday")
        #expect(parser.parse("%unix") == String(Int(parser.date!.timeIntervalSince1970)))
    }

    @Test func amPmSwitchesHourTo12HourFormat() {
        #expect(makeParser(hour: 9).parse("%h:%mi %pm") == "09:05 AM")
        #expect(makeParser(hour: 15).parse("%h:%mi %pm") == "03:05 PM")
        #expect(makeParser(hour: 0).parse("%h %pm") == "12 AM")
        // without %pm, hour stays 24h
        #expect(makeParser(hour: 15).parse("%h") == "15")
    }

    // MARK: Window and image codes

    @Test func windowTextIsSanitizedAndTruncated() {
        let parser = makeParser(.fileName)
        parser.windowText = "My File: Test"
        #expect(parser.parse("%t") == "My_File_Test")

        parser.maxTitleLength = 2
        #expect(parser.parse("%t") == "My")
    }

    @Test func imageDimensions() {
        let parser = makeParser()
        #expect(parser.parse("%width x %height") == " x ")
        parser.imageWidth = 1920
        parser.imageHeight = 1080
        #expect(parser.parse("%width x %height") == "1920 x 1080")
    }

    // MARK: Auto increment codes

    @Test func autoIncrement() {
        let parser = makeParser()
        parser.autoIncrementNumber = 5
        #expect(parser.parse("%i") == "6")
        #expect(parser.autoIncrementNumber == 6)
        #expect(parser.parse("%i{3}") == "007")
    }

    @Test func autoIncrementBases() {
        let parser = makeParser()
        parser.autoIncrementNumber = 254 // n becomes 255
        #expect(parser.parse("%i %ix %iX{4}") == "255 ff 00FF")

        parser.autoIncrementNumber = 36 // n becomes 37 = "11" base 36
        #expect(parser.parse("%ia") == "11")

        parser.autoIncrementNumber = 61 // n becomes 62 = "10" base 62
        #expect(parser.parse("%iAa") == "10")

        parser.autoIncrementNumber = 5 // n becomes 6 = "110" base 2, padded to 8
        #expect(parser.parse("%ib{2,8}") == "00000110")
    }

    @Test func noIncrementWithoutCode() {
        let parser = makeParser()
        parser.autoIncrementNumber = 5
        _ = parser.parse("%y")
        #expect(parser.autoIncrementNumber == 5)
    }

    // MARK: Random codes

    @Test func randomNumbers() {
        let result = makeParser().parse("%rn{5}")
        #expect(result.count == 5)
        #expect(result.allSatisfy { $0.isNumber })
    }

    @Test func randomAlphanumeric() {
        let result = makeParser().parse("%ra{16}")
        #expect(result.count == 16)
        #expect(result.allSatisfy { Chars.alphanumeric.contains($0) })
    }

    @Test func randomNonAmbiguous() {
        let result = makeParser().parse("%rna{20}")
        #expect(result.count == 20)
        #expect(result.allSatisfy { Chars.base56.contains($0) })
    }

    @Test func randomHex() {
        let lower = makeParser().parse("%rx{8}")
        #expect(lower.allSatisfy { "0123456789abcdef".contains($0) })
        let upper = makeParser().parse("%rX{8}")
        #expect(upper.allSatisfy { "0123456789ABCDEF".contains($0) })
    }

    @Test func guid() {
        let result = makeParser().parse("%guid")
        #expect(UUID(uuidString: result) != nil)
        #expect(result == result.lowercased())
        let upper = makeParser().parse("%GUID")
        #expect(upper == upper.uppercased())
    }

    @Test func randomWords() {
        let result = makeParser().parse("%radjective%ranimal")
        #expect(!result.isEmpty)
        #expect(!result.contains("%"))
    }

    @Test func eachOccurrenceGetsFreshRandomValue() {
        // 32 hex chars twice colliding by chance: p = 16^-32, effectively impossible
        let result = makeParser().parse("%rx{32}_%rx{32}")
        let parts = result.components(separatedBy: "_")
        #expect(parts[0] != parts[1])
    }

    // MARK: Newline

    @Test func newlineOnlyInTextType() {
        #expect(makeParser(.text).parse("a%nb") == "a\nb")
        #expect(makeParser(.default).parse("a%nb") == "a%nb")
    }

    // MARK: Output sanitizing

    @Test func fileNameSanitizing() {
        #expect(makeParser(.fileName).parse("%y/%mo") == "202403")
        #expect(makeParser(.fileName).parse("a:b*c?d") == "abcd")
    }

    @Test func filePathKeepsSeparators() {
        #expect(makeParser(.filePath).parse("%y/%mo") == "2024/03")
    }

    @Test func urlEncoding() {
        #expect(makeParser(.url).parse("a b") == "a%20b")
    }

    @Test func maxNameLength() {
        let parser = makeParser()
        parser.maxNameLength = 4
        #expect(parser.parse("%y-%mo-%d") == "2024")
    }

    @Test func emptyPattern() {
        #expect(makeParser().parse("") == "")
    }
}
