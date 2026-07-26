// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Background removal via Vision's subject-lifting mask (macOS 14+).
// Upstream v21 ships this with a user-downloaded ONNX model; Vision needs no
// model download and runs on the Neural Engine where available.

import CoreImage
import Vision

public enum BackgroundRemoverError: LocalizedError {
    case noSubject
    case renderFailed

    public var errorDescription: String? {
        switch self {
        case .noSubject: return "No foreground subject was detected in the image."
        case .renderFailed: return "Could not render the masked image."
        }
    }
}

public enum BackgroundRemover {
    /// Isolates the detected foreground subject(s); everything else becomes
    /// transparent. Synchronous and potentially slow (model inference) —
    /// call off the main thread.
    public static func removeBackground(from image: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw BackgroundRemoverError.noSubject
        }
        let maskBuffer = try observation.generateScaledMaskForImage(
            forInstances: observation.allInstances, from: handler)

        let source = CIImage(cgImage: image)
        let mask = CIImage(cvPixelBuffer: maskBuffer)
        guard let filter = CIFilter(name: "CIBlendWithMask") else {
            throw BackgroundRemoverError.renderFailed
        }
        filter.setValue(source, forKey: kCIInputImageKey)
        filter.setValue(CIImage(color: .clear).cropped(to: source.extent), forKey: kCIInputBackgroundImageKey)
        filter.setValue(mask, forKey: kCIInputMaskImageKey)
        guard let output = filter.outputImage,
              let rendered = CIContext().createCGImage(output, from: source.extent) else {
            throw BackgroundRemoverError.renderFailed
        }
        return rendered
    }
}
