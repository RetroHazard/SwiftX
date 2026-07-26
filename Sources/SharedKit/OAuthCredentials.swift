// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// OAuth destination identity + the app-credential gate. An OAuth host is
// enabled as soon as app credentials exist for it — either baked in from the
// bundled OAuthApps.plist (git-ignored; present in release builds) or pasted
// by the user in Settings → Advanced, which overrides the bundled entry.
// Without either, `isConfigured(_:)` returns false and the destination is
// greyed out / refuses to route. The switch is data, not a compile flag.

import Foundation

/// The OAuth2 destinations we can authenticate against. Raw values are the
/// `imageDestination` strings the pipeline routes on (and match the C#
/// ShareX destination names for Windows config import).
public enum OAuthProviderID: String, CaseIterable, Codable, Sendable {
    case googleDrive = "GoogleDrive"
    case oneDrive = "OneDrive"
    case youTube = "YouTube"
    // ponytail: Photobucket dropped (defunct API), Flickr deferred (OAuth1,
    // niche) — add an OAuth1Flow layer only if Flickr is ever wanted.
    // Imgur dropped (no longer issues app client IDs), Box dropped (developer
    // API gated behind a paid plan), Dropbox dropped by choice.

    public var displayName: String {
        switch self {
        case .googleDrive: return "Google Drive"
        case .oneDrive: return "OneDrive"
        case .youTube: return "YouTube"
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

/// App-level OAuth credentials that identify SwiftX itself to each host. These
/// are registered ONCE by the developer and shipped in the distributable — end
/// users never see them. They live in a bundled, git-ignored `OAuthApps.plist`
/// so real keys stay out of the open-source tree (see OAuthApps.example.plist).
///
/// A desktop app can't truly hide a client secret, so PKCE is the real
/// protection; hosts that support public clients (OneDrive) need no secret at
/// all. Google ships a semi-public desktop-client secret, as ShareX does.
public enum OAuthAppRegistry {
    private static let builtins: [String: OAuthAppCredentials] = load()

    private static func load() -> [String: OAuthAppCredentials] {
        guard let url = Bundle.main.url(forResource: "OAuthApps", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListDecoder().decode([String: OAuthAppCredentials].self, from: data)
        else { return [:] }
        return dict
    }

    /// The developer's registered credentials for a host, if this build shipped
    /// with them.
    public static func builtin(_ id: OAuthProviderID) -> OAuthAppCredentials? {
        guard let creds = builtins[id.rawValue], creds.isPresent else { return nil }
        return creds
    }
}

public extension UploadersConfig {
    /// A power-user override supplied in Settings → Advanced (their own OAuth
    /// app). Nil unless they entered a client ID.
    func oauthUserOverride(for id: OAuthProviderID) -> OAuthAppCredentials? {
        guard let creds = oauthApps[id.rawValue], creds.isPresent else { return nil }
        return creds
    }

    /// The credentials actually used to authenticate: a user override wins,
    /// otherwise the developer's baked-in app credentials.
    func oauthCredentials(for id: OAuthProviderID) -> OAuthAppCredentials? {
        oauthUserOverride(for: id) ?? OAuthAppRegistry.builtin(id)
    }

    /// True when the host can be connected — i.e. some app credentials exist.
    /// End users get here purely from the baked-in keys; no data entry needed.
    func isConfigured(_ id: OAuthProviderID) -> Bool {
        oauthCredentials(for: id) != nil
    }
}
