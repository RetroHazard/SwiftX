// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import Testing
@testable import SharedKit

struct CLIParserTests {
    @Test func urlSchemeMapsHostToVerbAndPathToParameter() {
        #expect(CLIParser.arguments(fromURL: URL(string: "swiftx://OCR")!) == ["-OCR"])
        #expect(CLIParser.arguments(fromURL: URL(string: "swiftx://workflow/My%20Task")!) == ["-workflow", "My Task"])
        #expect(CLIParser.arguments(fromURL: URL(string: "sharex://RectangleRegion/")!) == ["-RectangleRegion"])
        #expect(CLIParser.arguments(fromURL: URL(string: "swiftx://")!).isEmpty)
    }

    @Test func verbsParametersAndBareArgumentsParseLikeCSharp() {
        let commands = CLIParser.parse(
            ["-RectangleRegion", "-FileUpload", "/tmp/a.png", "shot.png", "-workflow", "OCR", "https://example.com/x.jpg"]
        )
        #expect(commands == [
            CLICommand(isCommand: true, command: "RectangleRegion"),
            CLICommand(isCommand: true, command: "FileUpload", parameter: "/tmp/a.png"),
            CLICommand(command: "shot.png"),
            CLICommand(isCommand: true, command: "workflow", parameter: "OCR"),
            CLICommand(command: "https://example.com/x.jpg")
        ])
    }

    @Test func matchesIsCaseInsensitiveAndCommandOnly() {
        #expect(CLICommand(isCommand: true, command: "customuploader").matches("CustomUploader"))
        #expect(!CLICommand(isCommand: false, command: "CustomUploader").matches("CustomUploader"))
    }
}
