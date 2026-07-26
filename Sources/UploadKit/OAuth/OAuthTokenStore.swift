// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
//
// OAuth tokens are secrets, so they live in the macOS Keychain (not the JSON
// config, unlike C# which encrypts them inline). OAuthSession ties the store
// to the flow: hand it a provider and it returns a valid bearer token,
// refreshing transparently.

import Foundation
import Security
import SharedKit

public enum OAuthTokenStore {
    static let service = "com.retrohazard.swiftx.oauth"

    public static func save(_ token: OAuth2Token, for id: OAuthProviderID) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        var query = baseQuery(id)
        SecItemDelete(query as CFDictionary)          // upsert: delete then add
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    public static func load(for id: OAuthProviderID) -> OAuth2Token? {
        var query = baseQuery(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(OAuth2Token.self, from: data)
    }

    public static func delete(for id: OAuthProviderID) {
        SecItemDelete(baseQuery(id) as CFDictionary)
    }

    /// True when a token is stored — used by the UI to show "Connected".
    public static func isConnected(_ id: OAuthProviderID) -> Bool {
        load(for: id) != nil
    }

    private static func baseQuery(_ id: OAuthProviderID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.rawValue]
    }
}

public enum OAuthSession {
    /// Returns a bearer token ready for an Authorization header, refreshing if
    /// the stored one is expired. Throws the precise gate error otherwise.
    public static func validAccessToken(for id: OAuthProviderID, config: UploadersConfig) async throws -> String {
        guard let credentials = config.oauthCredentials(for: id) else {
            throw OAuthError.notConfigured(id.displayName)
        }
        guard var token = OAuthTokenStore.load(for: id) else {
            throw OAuthError.notAuthenticated(id.displayName)
        }
        guard token.isExpired() else { return token.accessToken }
        guard !token.refreshToken.isEmpty else {
            // expired and no way to refresh — force a reconnect
            throw OAuthError.notAuthenticated(id.displayName)
        }

        let provider = OAuthProvider.provider(id)
        let request = OAuth2Flow.refreshRequest(provider: provider, credentials: credentials,
                                                refreshToken: token.refreshToken)
        let (data, response) = try await UploadHTTP.data(for: request)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true,
              var refreshed = try? OAuth2Flow.parseTokenResponse(data) else {
            throw OAuthError.tokenRefreshFailed(id.displayName)
        }
        // servers usually omit the refresh token on refresh — keep the old one
        if refreshed.refreshToken.isEmpty { refreshed.refreshToken = token.refreshToken }
        OAuthTokenStore.save(refreshed, for: id)
        token = refreshed
        return token.accessToken
    }
}
