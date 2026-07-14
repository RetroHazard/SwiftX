// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import Testing
@testable import SharedKit

struct CLIParserTests {
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
