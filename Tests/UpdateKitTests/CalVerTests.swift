// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import Foundation
import Testing
@testable import UpdateKit

struct CalVerTests {
    @Test func parsesPlainVersion() {
        let version = CalVer("2026.7.1")
        #expect(version?.year == 2026)
        #expect(version?.month == 7)
        #expect(version?.patch == 1)
        #expect(version?.description == "2026.7.1")
    }

    @Test func parsesTagForm() {
        #expect(CalVer("v2026.7.1") == CalVer("2026.7.1"))
    }

    @Test func stripsPrereleaseSuffix() {
        #expect(CalVer("2026.7.1-beta.1") == CalVer("2026.7.1"))
        #expect(CalVer("v2026.12.3-rc2") == CalVer("2026.12.3"))
    }

    @Test func rejectsMalformedStrings() {
        #expect(CalVer("") == nil)
        #expect(CalVer("2026.7") == nil)
        #expect(CalVer("2026.7.1.2") == nil)
        #expect(CalVer("abc") == nil)
        #expect(CalVer("2026.x.1") == nil)
        #expect(CalVer("2026..1") == nil)
        #expect(CalVer("-2026.7.1") == nil)
        #expect(CalVer("0.7.1") == nil)
        #expect(CalVer("2026.0.1") == nil)
    }

    @Test func ordersCalendarwise() throws {
        let ordered = try ["2026.7.1", "2026.7.2", "2026.8.1", "2026.12.10", "2027.1.1"]
            .map { try #require(CalVer($0)) }
        for (older, newer) in zip(ordered, ordered.dropFirst()) {
            #expect(older < newer)
            #expect(newer > older)
        }
    }

    @Test func numericNotLexicographicComparison() {
        // "2026.10.x" > "2026.9.x" even though "10" < "9" as strings
        #expect(CalVer("2026.9.1")! < CalVer("2026.10.1")!)
    }
}
