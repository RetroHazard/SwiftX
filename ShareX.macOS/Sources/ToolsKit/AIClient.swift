// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// AI image analysis over the OpenAI chat-completions wire format. C# ships
// separate OpenAI/Gemini/OpenRouter providers; all three speak this format
// (Gemini via its /openai compatibility path), so one client with a
// configurable base URL covers them.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct AIConfiguration: Sendable {
    public var baseURL: String
    public var apiKey: String
    public var model: String

    public init(baseURL: String, apiKey: String, model: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
    }
}

public enum AIClient {
    public enum AIError: LocalizedError {
        case missingKey, badURL, encodingFailed
        case http(Int, String)
        case emptyResponse

        public var errorDescription: String? {
            switch self {
            case .missingKey: return "Set an API key in the AI analysis window first."
            case .badURL: return "The AI base URL is not a valid URL."
            case .encodingFailed: return "The image could not be encoded."
            case .http(let status, let body): return "The AI service returned HTTP \(status): \(body)"
            case .emptyResponse: return "The AI service returned no content."
            }
        }
    }

    /// Chat-completions body: prompt text plus the image as a base64 data URI.
    static func requestBody(prompt: String, pngData: Data, model: String) throws -> Data {
        let payload: [String: Any] = [
            "model": model,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url",
                     "image_url": ["url": "data:image/png;base64," + pngData.base64EncodedString()]]
                ]
            ]]
        ]
        return try JSONSerialization.data(withJSONObject: payload)
    }

    static func parseResponse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty
        else { throw AIError.emptyResponse }
        return content
    }

    public static func analyze(image: CGImage, prompt: String, config: AIConfiguration) async throws -> String {
        guard !config.apiKey.isEmpty else { throw AIError.missingKey }
        guard let url = URL(string: config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")))?
            .appendingPathComponent("chat/completions") else { throw AIError.badURL }

        let pngData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            pngData, UTType.png.identifier as CFString, 1, nil
        ) else { throw AIError.encodingFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw AIError.encodingFailed }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try requestBody(prompt: prompt, pngData: pngData as Data, model: config.model)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIError.http(http.statusCode, String(data: data.prefix(300), encoding: .utf8) ?? "")
        }
        return try parseResponse(data)
    }
}
