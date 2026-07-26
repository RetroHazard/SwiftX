// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import Testing
@testable import ToolsKit

struct AIClientTests {
    @Test func requestBodyCarriesModelPromptAndImage() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let body = try AIClient.requestBody(prompt: "Describe this", pngData: png, model: "gpt-5-mini")
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "gpt-5-mini")

        let messages = try #require(json["messages"] as? [[String: Any]])
        let content = try #require(messages[0]["content"] as? [[String: Any]])
        #expect(content[0]["text"] as? String == "Describe this")
        let imagePart = try #require(content[1]["image_url"] as? [String: String])
        #expect(imagePart["url"]?.hasPrefix("data:image/png;base64,") == true)
        #expect(imagePart["url"]?.hasSuffix(png.base64EncodedString()) == true)
    }

    @Test func parsesChatCompletionResponse() throws {
        let response = Data("""
        {"choices":[{"message":{"role":"assistant","content":"A red square."}}]}
        """.utf8)
        #expect(try AIClient.parseResponse(response) == "A red square.")
    }

    @Test func emptyOrMalformedResponsesThrow() {
        #expect(throws: AIClient.AIError.self) {
            try AIClient.parseResponse(Data("{}".utf8))
        }
        #expect(throws: AIClient.AIError.self) {
            try AIClient.parseResponse(Data(#"{"choices":[{"message":{"content":""}}]}"#.utf8))
        }
    }
}
