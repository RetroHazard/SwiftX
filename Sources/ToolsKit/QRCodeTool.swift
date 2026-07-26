// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// QR generate (Core Image) and decode (Vision). C# QRCodeForm uses ZXing;
// both ends here are system frameworks, no dependency needed.

import CoreImage
@preconcurrency import Vision

public enum QRCodeTool {
    /// QR code for `text`, scaled with hard pixel edges to roughly `size`.
    public static func generate(_ text: String, size: CGFloat = 512) -> CGImage? {
        guard !text.isEmpty, let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = (size / output.extent.width).rounded(.down)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: max(1, scale), y: max(1, scale)))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }

    /// Payloads of every QR code found in the image.
    public static func decode(_ image: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.compactMap { $0.payloadStringValue } ?? []
    }
}

public enum ImageLoader {
    /// First frame of any image file Image I/O can read.
    public static func load(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
