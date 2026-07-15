// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// OAuth destination identity + the app-credential gate. Every OAuth host is
// DISABLED until its client ID is supplied: `oauthApps` is empty by default,
// so `isConfigured(_:)` returns false and the destination is greyed out /
// refuses to route. Pasting credentials in Settings enables it with no code
// change and no rebuild — the switch is data, not a compile flag.

import Foundation

/// The OAuth2 destinations we can authenticate against. Raw values are the
/// `imageDestination` strings the pipeline routes on (and match the C#
/// ShareX destination names for Windows config import).
public enum OAuthProviderID: String, CaseIterable, Codable, Sendable {
    case googleDrive = "GoogleDrive"
    case dropbox = "Dropbox"
    case oneDrive = "OneDrive"
    case box = "Box"
    case youTube = "YouTube"
    case imgur = "Imgur"
    // ponytail: Photobucket dropped (defunct API), Flickr deferred (OAuth1,
    // niche) — add an OAuth1Flow layer only if Flickr is ever wanted.

    public var displayName: String {
        switch self {
        case .googleDrive: return "Google Drive"
        case .dropbox: return "Dropbox"
        case .oneDrive: return "OneDrive"
        case .box: return "Box"
        case .youTube: return "YouTube"
        case .imgur: return "Imgur"
        }
    }
}

/// The client ID / secret the user obtains by registering an app with a host.
/// Empty by default; presence of a client ID is what enables the destination.
public struct OAuthAppCredentials: Codable, Equatable, Sendable {
    public var clientID = ""
    public var clientSecret = ""

    public init(clientID: String = "", clientSecret: String = "") {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }

    /// A secret is optional (PKCE public clients omit it), so the client ID
    /// alone decides whether the host is set up.
    public var isPresent: Bool { !clientID.trimmingCharacters(in: .whitespaces).isEmpty }

    enum CodingKeys: String, CodingKey {
        case clientID = "ClientID"
        case clientSecret = "ClientSecret"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        clientID = try c.decodeIfPresent(String.self, forKey: .clientID) ?? ""
        clientSecret = try c.decodeIfPresent(String.self, forKey: .clientSecret) ?? ""
    }
}

public extension UploadersConfig {
    /// Returns the credentials only when a client ID is present — the gate.
    func oauthCredentials(for id: OAuthProviderID) -> OAuthAppCredentials? {
        guard let creds = oauthApps[id.rawValue], creds.isPresent else { return nil }
        return creds
    }

    /// True once the user has supplied an app client ID for this host.
    func isConfigured(_ id: OAuthProviderID) -> Bool {
        oauthCredentials(for: id) != nil
    }
}
