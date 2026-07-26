// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Upload progress plumbing. The coordinator binds a task-local reporter
// around an upload; every HTTP request the uploaders make through
// UploadHTTP then streams body-upload progress to it. No uploader
// signatures change, and code outside an upload pays nothing.

import Foundation

/// Receives (bytesSent, bytesExpected) for the request currently on the wire.
/// Multi-request uploaders (B2 auth, Seafile share, ...) report per request;
/// the payload request dominates, so the bar reads correctly in practice.
public final class UploadProgressReporter: Sendable {
    public let onProgress: @Sendable (Int64, Int64) -> Void

    public init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onProgress = onProgress
    }

    @TaskLocal public static var current: UploadProgressReporter?
}

/// Drop-in replacement for URLSession.shared.data(for:) inside UploadKit.
public enum UploadHTTP {
    public static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let reporter = UploadProgressReporter.current else {
            return try await URLSession.shared.data(for: request)
        }
        return try await URLSession.shared.data(for: request, delegate: ProgressDelegate(reporter: reporter))
    }
}

private final class ProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let reporter: UploadProgressReporter

    init(reporter: UploadProgressReporter) {
        self.reporter = reporter
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        reporter.onProgress(totalBytesSent, totalBytesExpectedToSend)
    }
}
