// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import Testing
@testable import SharedKit

struct ResultURLTests {
    @Test func templateReplacesResultToken() {
        #expect(ResultURL.format("$result", result: "https://x/1.png") == "https://x/1.png")
        #expect(ResultURL.format("![]($result)", result: "https://x/1.png") == "![](https://x/1.png)")
        #expect(ResultURL.format("", result: "https://x/1.png") == "https://x/1.png")
        // multiple tokens all substitute
        #expect(ResultURL.format("[$result]($result)", result: "u") == "[u](u)")
    }

    @Test func regexReplaceAppliesTemplate() {
        #expect(ResultURL.regexReplaced("https://i.imgur.com/abc.png",
                                        pattern: "i\\.imgur\\.com", replacement: "imgur.com")
                == "https://imgur.com/abc.png")
        // capture groups via $1
        #expect(ResultURL.regexReplaced("https://host/u/abc", pattern: "/u/(\\w+)$", replacement: "/direct/$1")
                == "https://host/direct/abc")
    }

    @Test func regexReplaceToleratesBadInput() {
        // invalid pattern: URL passes through instead of failing the task
        #expect(ResultURL.regexReplaced("https://x/1", pattern: "(", replacement: "y") == "https://x/1")
        #expect(ResultURL.regexReplaced("https://x/1", pattern: "", replacement: "y") == "https://x/1")
    }

    @Test func forcedHTTPSOnlyRewritesTheScheme() {
        #expect(ResultURL.forcedHTTPS("http://x/http://nested") == "https://x/http://nested")
        #expect(ResultURL.forcedHTTPS("https://already") == "https://already")
        #expect(ResultURL.forcedHTTPS("ftp://other") == "ftp://other")
    }

    @Test func problematicCharactersAreReplaced() {
        #expect(ResultURL.problematicCharactersReplaced("my file (1).png") == "my_file_1.png")
        #expect(ResultURL.problematicCharactersReplaced("Ünïcode & spaces.jpg") == "ncode__spaces.jpg")
        #expect(ResultURL.problematicCharactersReplaced("clean-name_2.png") == "clean-name_2.png")
    }

    @Test func forTaskParserHonorsCustomTimeZone() {
        var settings = TaskSettings()
        settings.useCustomTimeZone = true
        settings.customTimeZoneIdentifier = "UTC"
        let parser = NameParser.forTask(.fileName, settings: settings)
        // 2024-03-07 12:00:00 UTC — %h must be 12 regardless of local zone
        parser.date = Date(timeIntervalSince1970: 1709812800)
        #expect(parser.parse("%h") == "12")

        // unknown identifier falls back to local time (no crash, zone unset)
        settings.customTimeZoneIdentifier = "Not/AZone"
        #expect(NameParser.forTask(.fileName, settings: settings).customTimeZone == nil)

        settings.useCustomTimeZone = false
        #expect(NameParser.forTask(.fileName, settings: settings).customTimeZone == nil)
    }
}
