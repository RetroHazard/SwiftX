// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt
//
// OCR via the Vision framework. C# uses Windows.Media.Ocr with a language
// picker; Vision detects the language itself, so no OCROptions.Language port.

import CoreGraphics
// Vision request objects predate Sendable; the request is only touched
// from its own completion handler, so the capture is safe.
@preconcurrency import Vision

public enum OCRService {
    /// Recognized lines joined with newlines, in reading order.
    public static func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: image).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
