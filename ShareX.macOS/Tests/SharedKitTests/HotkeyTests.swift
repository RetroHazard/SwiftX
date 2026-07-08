// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import Testing
@testable import SharedKit

struct KeyComboTests {
    @Test func carbonKeyCodes() {
        #expect(KeyCombo(key: "4", modifiers: []).carbonKeyCode == 21)
        #expect(KeyCombo(key: "a", modifiers: []).carbonKeyCode == 0)
        #expect(KeyCombo(key: "F12", modifiers: []).carbonKeyCode == 111) // case-insensitive
        #expect(KeyCombo(key: "space", modifiers: []).carbonKeyCode == 49)
        #expect(KeyCombo(key: "µ", modifiers: []).carbonKeyCode == nil)
    }

    @Test func carbonModifierMask() {
        let combo = KeyCombo(key: "4", modifiers: ["control", "shift"])
        #expect(combo.carbonModifiers == 0x1200) // controlKey | shiftKey
        let all = KeyCombo(key: "4", modifiers: ["command", "option", "control", "shift"])
        #expect(all.carbonModifiers == 0x1B00) // cmd 0x100 | shift 0x200 | option 0x800 | control 0x1000
        // aliases
        #expect(KeyCombo(key: "4", modifiers: ["cmd", "alt"]).carbonModifiers == 0x0900)
    }

    @Test func displayStringUsesMacOSModifierOrder() {
        #expect(KeyCombo(key: "4", modifiers: ["shift", "control"]).displayString == "⌃⇧4")
        #expect(KeyCombo(key: "space", modifiers: ["command"]).displayString == "⌘Space")
        #expect(KeyCombo(key: "escape", modifiers: []).displayString == "⎋")
    }

    @Test func hotkeyConfigJSONShape() throws {
        let config = HotkeyConfig(.rectangleRegion, key: "4", modifiers: ["control", "shift"])
        let data = try JSONEncoder().encode(config)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("\"TaskType\":\"RectangleRegion\""))
        #expect(json.contains("\"Key\":\"4\""))

        let decoded = try JSONDecoder().decode(HotkeyConfig.self, from: data)
        #expect(decoded == config)
        #expect(decoded.type == .rectangleRegion)
        #expect(decoded.combo == KeyCombo(key: "4", modifiers: ["control", "shift"]))
    }

    @Test func unknownTaskTypeStillLoads() throws {
        let json = #"{"TaskType": "SomeFutureFeature", "Key": "9", "Modifiers": ["command"]}"#
        let decoded = try JSONDecoder().decode(HotkeyConfig.self, from: json.data(using: .utf8)!)
        #expect(decoded.type == nil) // unknown, but not an error
        #expect(decoded.combo?.carbonKeyCode == 25)
    }

    @Test func hotkeyTypeRawValuesMatchCSharpNames() {
        // spot-check the vocabulary contract with the C# enum
        #expect(HotkeyType.rectangleRegion.rawValue == "RectangleRegion")
        #expect(HotkeyType.printScreen.rawValue == "PrintScreen")
        #expect(HotkeyType.screenRecorderGIF.rawValue == "ScreenRecorderGIF")
        #expect(HotkeyType.ocr.rawValue == "OCR")
        #expect(HotkeyType.allCases.count > 60)
    }
}
