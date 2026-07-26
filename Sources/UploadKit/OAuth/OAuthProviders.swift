// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// Static descriptors for each OAuth2 host: authorize/token endpoints, scopes
// and quirks. These are public, credential-free constants — the client ID/
// secret come from UploadersConfig at run time.

import Foundation
import SharedKit

public struct OAuthProvider: Sendable {
    public let id: OAuthProviderID
    public let authorizeURL: String
    public let tokenURL: String
    public let scopes: [String]
    /// Every host here supports PKCE; the flag stays so a future host whose
    /// server rejects the `code_challenge` parameters can opt out.
    public let usesPKCE: Bool
    /// Extra authorize-query params (e.g. Google needs these to return a
    /// refresh token for a desktop app).
    public let extraAuthorizeParams: [String: String]

    public var displayName: String { id.displayName }

    public static let all: [OAuthProviderID: OAuthProvider] = [
        .googleDrive: OAuthProvider(
            id: .googleDrive,
            authorizeURL: "https://accounts.google.com/o/oauth2/v2/auth",
            tokenURL: "https://oauth2.googleapis.com/token",
            scopes: ["https://www.googleapis.com/auth/drive.file"],
            usesPKCE: true,
            // offline + consent forces a refresh_token on the first grant
            extraAuthorizeParams: ["access_type": "offline", "prompt": "consent"]),
        .youTube: OAuthProvider(
            id: .youTube,
            authorizeURL: "https://accounts.google.com/o/oauth2/v2/auth",
            tokenURL: "https://oauth2.googleapis.com/token",
            scopes: ["https://www.googleapis.com/auth/youtube.upload"],
            usesPKCE: true,
            extraAuthorizeParams: ["access_type": "offline", "prompt": "consent"]),
        .oneDrive: OAuthProvider(
            id: .oneDrive,
            authorizeURL: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
            tokenURL: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
            scopes: ["Files.ReadWrite", "offline_access"],
            usesPKCE: true,
            extraAuthorizeParams: [:])
    ]

    public static func provider(_ id: OAuthProviderID) -> OAuthProvider {
        // all cases are present in `all`; force-unwrap keeps callers clean
        all[id]!
    }
}
