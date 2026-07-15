// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt
//
// Catches the OAuth redirect on http://127.0.0.1:<port>/. We use a loopback
// listener rather than a custom URL scheme because Google/Dropbox/Microsoft
// reject non-loopback redirect URIs for desktop clients — this mirrors what
// C# ShareX does with its HttpListener.

import Foundation
import Network

/// Starts a one-shot HTTP listener on a random loopback port, hands back its
/// redirect URI, and resolves once the browser hits it with `?code=...`.
public final class LoopbackRedirect: @unchecked Sendable {
    private let listener: NWListener
    public let port: UInt16
    private var continuation: CheckedContinuation<[String: String], Error>?
    private let queue = DispatchQueue(label: "com.retrohazard.swiftx.oauth.loopback")

    public init() throws {
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        let listener = try NWListener(using: params)
        self.listener = listener
        // resolve the OS-assigned port after start; 0 means "pick one"
        var assigned: UInt16 = 0
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { assigned = listener.port?.rawValue ?? 0; ready.signal() }
            if case .failed = state { ready.signal() }
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        guard assigned != 0 else { throw OAuthError.authorizationFailed("could not open a loopback port") }
        port = assigned
    }

    public var redirectURI: String { "http://127.0.0.1:\(port)/" }

    /// Awaits the redirect and returns its query parameters (`code`/`state` or
    /// `error`). Times out after 5 minutes so a cancelled login can't hang.
    public func waitForCallback() async throws -> [String: String] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                self.continuation = cont
                self.listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
                self.queue.asyncAfter(deadline: .now() + 300) { [weak self] in
                    self?.finish(.failure(OAuthError.authorizationFailed("timed out waiting for the browser")))
                }
            }
        } onCancel: {
            self.finish(.failure(CancellationError()))
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                conn.cancel(); return
            }
            let params = Self.queryParams(fromRequestLine: request)
            let body = "<html><body style='font-family:-apple-system'>You can close this window and return to SwiftX.</body></html>"
            let http = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            conn.send(content: Data(http.utf8), completion: .contentProcessed { _ in conn.cancel() })
            self.finish(.success(params))
        }
    }

    /// Extracts `?a=b&c=d` from the request line `GET /?a=b&c=d HTTP/1.1`.
    static func queryParams(fromRequestLine request: String) -> [String: String] {
        guard let line = request.split(separator: "\r\n").first,
              let pathPart = line.split(separator: " ").dropFirst().first,
              let query = pathPart.split(separator: "?").dropFirst().first else { return [:] }
        var result: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard let key = kv.first else { continue }
            let value = kv.count > 1 ? String(kv[1]) : ""
            result[String(key)] = value.removingPercentEncoding ?? value
        }
        return result
    }

    private func finish(_ result: Result<[String: String], Error>) {
        queue.async {
            guard let cont = self.continuation else { return }
            self.continuation = nil
            self.listener.cancel()
            cont.resume(with: result)
        }
    }
}
