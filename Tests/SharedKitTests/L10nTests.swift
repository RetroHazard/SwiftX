// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE

import Foundation
import Testing
@testable import SharedKit

// Serialized: the suite mutates the shared L10n override.
@Suite(.serialized)
struct L10nTests {
    @Test func englishKeyResolves() {
        L10n.shared.apply(languageCode: "en")
        defer { L10n.shared.apply(languageCode: nil) }
        #expect(L10n.t("common.cancel") == "Cancel")
    }

    @Test func missingKeyReturnsKey() {
        #expect(L10n.t("no.such.key.anywhere") == "no.such.key.anywhere")
        #expect(!L10n.has("no.such.key.anywhere"))
        #expect(L10n.has("common.cancel"))
    }

    @Test func unknownLanguageFallsBackToShippedLanguage() {
        L10n.shared.apply(languageCode: "xx-YY")
        defer { L10n.shared.apply(languageCode: nil) }
        #expect(L10n.t("common.ok") == "OK")
    }

    @Test func availableLanguagesContainsEnglish() {
        #expect(L10n.availableLanguages.contains("en"))
        #expect(!L10n.availableLanguages.contains("Base"))
    }

    @Test func formatArgumentsAreSubstituted() {
        L10n.shared.apply(languageCode: "en")
        defer { L10n.shared.apply(languageCode: nil) }
        // Any %@ key works; the language picker's restart body has none, so
        // exercise the formatter through a key-miss (format of the key itself).
        #expect(L10n.t("literal %@ passthrough", "X") == "literal X passthrough")
    }

    @Test func systemDefaultResolvesToAShippedLanguage() {
        L10n.shared.apply(languageCode: nil)
        // 7 languages now compete for system-preference resolution, so which
        // one wins depends on the runner's own locale - only assert the key
        // resolved to a real translation, not a specific one.
        #expect(L10n.t("common.quit") != "common.quit")
    }

    @Test func displayNameIncludesNativeName() {
        #expect(L10n.displayName(for: "en").lowercased().contains("english"))
    }

    @Test func interfaceLanguageRoundTripsThroughConfig() throws {
        var config = ApplicationConfig()
        #expect(config.interfaceLanguage == "")
        config.interfaceLanguage = "fr"
        let data = try JSONEncoder().encode(config)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"InterfaceLanguage\":\"fr\""))
        let decoded = try JSONDecoder().decode(ApplicationConfig.self, from: data)
        #expect(decoded.interfaceLanguage == "fr")
    }
}
