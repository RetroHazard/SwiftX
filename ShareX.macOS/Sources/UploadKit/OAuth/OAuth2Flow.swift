// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt
//
// Pure OAuth2 authorization-code (+PKCE) request building. No network here —
// callers send the requests; these functions are unit-tested offline exactly
// like SimpleHostUploader.request().

import Foundation
import SharedKit

public enum OAuth2Flow {
    /// The browser URL that starts the consent flow.
    public static func authorizeURL(provider: OAuthProvider, credentials: OAuthAppCredentials,
                                    redirectURI: String, state: String, pkce: PKCE?) -> URL {
        var components = URLComponents(string: provider.authorizeURL)!
        var items = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: state)
        ]
        if !provider.scopes.isEmpty {
            items.append(URLQueryItem(name: "scope", value: provider.scopes.joined(separator: " ")))
        }
        if provider.usesPKCE, let pkce {
            items.append(URLQueryItem(name: "code_challenge", value: pkce.challenge))
            items.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        }
        for (key, value) in provider.extraAuthorizeParams.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items
        return components.url!
    }

    /// Exchanges the returned `code` for tokens (form-urlencoded POST).
    public static func tokenExchangeRequest(provider: OAuthProvider, credentials: OAuthAppCredentials,
                                            code: String, redirectURI: String, pkce: PKCE?) -> URLRequest {
        var fields = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": credentials.clientID
        ]
        if !credentials.clientSecret.isEmpty { fields["client_secret"] = credentials.clientSecret }
        if provider.usesPKCE, let pkce { fields["code_verifier"] = pkce.verifier }
        return formRequest(url: provider.tokenURL, fields: fields)
    }

    /// Trades a refresh token for a fresh access token.
    public static func refreshRequest(provider: OAuthProvider, credentials: OAuthAppCredentials,
                                      refreshToken: String) -> URLRequest {
        var fields = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": credentials.clientID
        ]
        if !credentials.clientSecret.isEmpty { fields["client_secret"] = credentials.clientSecret }
        return formRequest(url: provider.tokenURL, fields: fields)
    }

    /// Parses a token endpoint JSON body into an OAuth2Token, folding
    /// `expires_in` (seconds) into an absolute `expiresAt`.
    public static func parseTokenResponse(_ data: Data, now: Date = Date()) throws -> OAuth2Token {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            throw OAuthError.invalidTokenResponse
        }
        var expiresAt: Date?
        if let seconds = json["expires_in"] as? Double {
            expiresAt = now.addingTimeInterval(seconds)
        } else if let seconds = (json["expires_in"] as? String).flatMap(Double.init) {
            expiresAt = now.addingTimeInterval(seconds)
        }
        return OAuth2Token(
            accessToken: accessToken,
            tokenType: json["token_type"] as? String ?? "Bearer",
            refreshToken: json["refresh_token"] as? String ?? "",
            scope: json["scope"] as? String ?? "",
            expiresAt: expiresAt)
    }

    // MARK: - Helpers

    static func formRequest(url: String, fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(encodeForm(fields).utf8)
        return request
    }

    /// Sorted so the encoded body is deterministic (tests + stable diffs).
    static func encodeForm(_ fields: [String: String]) -> String {
        fields.sorted { $0.key < $1.key }
            .map { "\(formEncode($0.key))=\(formEncode($0.value))" }
            .joined(separator: "&")
    }

    /// application/x-www-form-urlencoded: RFC 3986 unreserved kept, space → %20.
    static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}
