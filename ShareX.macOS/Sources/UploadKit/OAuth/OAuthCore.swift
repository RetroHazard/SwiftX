// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// OAuth2 primitives shared by the flow, token store and uploaders: the error
// set, the persisted token model, and the small crypto used by PKCE. All of
// this is credential-independent and unit-tested offline.

import Foundation
import Security
import CryptoKit
import SharedKit

public enum OAuthError: LocalizedError, Equatable {
    /// No client ID supplied for the host — the gate is closed.
    case notConfigured(String)
    /// Configured, but the user hasn't connected an account yet.
    case notAuthenticated(String)
    case tokenRefreshFailed(String)
    case invalidTokenResponse
    case authorizationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let name):
            return "\(name) needs OAuth app credentials. Add a client ID in Settings → Upload destination."
        case .notAuthenticated(let name):
            return "Not connected to \(name). Click Connect in Settings → Upload destination."
        case .tokenRefreshFailed(let name):
            return "Could not refresh the \(name) session. Reconnect in Settings."
        case .invalidTokenResponse:
            return "The authorization server returned an unexpected response."
        case .authorizationFailed(let reason):
            return "Authorization failed: \(reason)"
        }
    }
}

/// Persisted OAuth2 token. Field names mirror C# ShareX's OAuth2Info so a
/// Windows backup could be imported later; the blob itself lives in the
/// Keychain (see OAuthTokenStore), not in the JSON config.
public struct OAuth2Token: Codable, Equatable, Sendable {
    public var accessToken: String
    public var tokenType: String
    public var refreshToken: String
    public var scope: String
    /// Absolute expiry, computed from the response's `expires_in`.
    public var expiresAt: Date?

    public init(accessToken: String, tokenType: String = "Bearer", refreshToken: String = "",
                scope: String = "", expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.refreshToken = refreshToken
        self.scope = scope
        self.expiresAt = expiresAt
    }

    /// True within 60s of expiry (skew guard), matching C#'s early refresh.
    public func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return now.addingTimeInterval(60) >= expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case tokenType = "TokenType"
        case refreshToken = "RefreshToken"
        case scope = "Scope"
        case expiresAt = "ExpiresAt"
    }
}

/// Proof Key for Code Exchange (RFC 7636), S256 method. The verifier is a
/// random URL-safe string; the challenge is base64url(SHA256(verifier)).
public struct PKCE: Equatable, Sendable {
    public let verifier: String
    public let challenge: String

    /// Deterministic init (used by tests with the RFC 7636 vector).
    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = OAuthCrypto.base64URL(OAuthCrypto.sha256(verifier))
    }

    public static func generate() -> PKCE {
        PKCE(verifier: OAuthCrypto.randomURLSafe(byteCount: 32))
    }
}

/// Small crypto helpers. Kept pure so PKCE has a runnable self-check.
public enum OAuthCrypto {
    /// base64url without padding (`+/=` → `-_`, stripped).
    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func sha256(_ string: String) -> Data {
        Data(SHA256.hash(data: Data(string.utf8)))
    }

    /// Cryptographically random, base64url-encoded — a valid PKCE verifier
    /// (43 chars for 32 bytes) and OAuth `state`.
    public static func randomURLSafe(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        // ponytail: SecRandom is the OS CSPRNG; falls back to arc4random only
        // if it ever fails, which it effectively never does on macOS.
        if SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) != errSecSuccess {
            for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        }
        return base64URL(Data(bytes))
    }
}
