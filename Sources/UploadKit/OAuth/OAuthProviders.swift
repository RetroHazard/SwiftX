// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
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
    /// PKCE is used by every host here except Imgur, whose server rejects the
    /// `code_challenge` parameters.
    public let usesPKCE: Bool
    /// Extra authorize-query params (e.g. Google/Dropbox need these to return
    /// a refresh token for a desktop app).
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
        .dropbox: OAuthProvider(
            id: .dropbox,
            authorizeURL: "https://www.dropbox.com/oauth2/authorize",
            tokenURL: "https://api.dropboxapi.com/oauth2/token",
            scopes: ["files.content.write", "sharing.write"],
            usesPKCE: true,
            // offline access → refresh token (Dropbox tokens are short-lived)
            extraAuthorizeParams: ["token_access_type": "offline"]),
        .oneDrive: OAuthProvider(
            id: .oneDrive,
            authorizeURL: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
            tokenURL: "https://login.microsoftonline.com/common/oauth2/v2.0/token",
            scopes: ["Files.ReadWrite", "offline_access"],
            usesPKCE: true,
            extraAuthorizeParams: [:]),
        .box: OAuthProvider(
            id: .box,
            authorizeURL: "https://account.box.com/api/oauth2/authorize",
            tokenURL: "https://api.box.com/oauth2/token",
            scopes: [],
            usesPKCE: true,
            extraAuthorizeParams: [:]),
        .imgur: OAuthProvider(
            id: .imgur,
            authorizeURL: "https://api.imgur.com/oauth2/authorize",
            tokenURL: "https://api.imgur.com/oauth2/token",
            scopes: [],
            usesPKCE: false,
            extraAuthorizeParams: [:])
    ]

    public static func provider(_ id: OAuthProviderID) -> OAuthProvider {
        // all cases are present in `all`; force-unwrap keeps callers clean
        all[id]!
    }
}
