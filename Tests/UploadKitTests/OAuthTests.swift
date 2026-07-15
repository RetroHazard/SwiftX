// ShareX - A program that allows you to take screenshots and share any file type
// Copyright (c) 2007-2026 ShareX Team
// Licensed under GPL v3 - see /LICENSE.txt

import Foundation
import Testing
@testable import UploadKit
@testable import SharedKit

struct OAuthTests {
    // MARK: - PKCE (RFC 7636 Appendix B test vector)

    @Test func pkceChallengeMatchesRFC7636Vector() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generatedVerifierIsURLSafeAndLongEnough() {
        let pkce = PKCE.generate()
        // 32 random bytes → 43 base64url chars, all from the unreserved set
        #expect(pkce.verifier.count >= 43)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        #expect(pkce.verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    // MARK: - Authorize URL

    @Test func authorizeURLCarriesPKCEAndScopes() throws {
        let provider = OAuthProvider.provider(.googleDrive)
        let creds = OAuthAppCredentials(clientID: "abc.apps.googleusercontent.com", clientSecret: "shh")
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = OAuth2Flow.authorizeURL(provider: provider, credentials: creds,
                                          redirectURI: "http://127.0.0.1:5000/", state: "xyz", pkce: pkce)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
        let dict = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(dict["response_type"] == "code")
        #expect(dict["client_id"] == "abc.apps.googleusercontent.com")
        #expect(dict["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(dict["code_challenge_method"] == "S256")
        #expect(dict["scope"] == "https://www.googleapis.com/auth/drive.file")
        #expect(dict["access_type"] == "offline")   // extra param, required for a refresh token
        #expect(dict["state"] == "xyz")
    }

    @Test func imgurAuthorizeURLOmitsPKCE() {
        let provider = OAuthProvider.provider(.imgur)
        let creds = OAuthAppCredentials(clientID: "id", clientSecret: "secret")
        let url = OAuth2Flow.authorizeURL(provider: provider, credentials: creds,
                                          redirectURI: "http://127.0.0.1:5000/", state: "s", pkce: PKCE.generate())
        let names = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map(\.name)
        #expect(!names.contains("code_challenge"))
    }

    // MARK: - Token requests

    @Test func tokenExchangeBodyIsFormEncoded() throws {
        let provider = OAuthProvider.provider(.dropbox)
        let creds = OAuthAppCredentials(clientID: "cid", clientSecret: "csecret")
        let pkce = PKCE(verifier: "verifier123")
        let request = OAuth2Flow.tokenExchangeRequest(provider: provider, credentials: creds,
                                                      code: "the code", redirectURI: "http://127.0.0.1:5000/", pkce: pkce)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code=the%20code"))       // space percent-encoded
        #expect(body.contains("client_secret=csecret"))
        #expect(body.contains("code_verifier=verifier123"))
    }

    @Test func parseTokenResponseFoldsExpiresIn() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let json = Data(#"{"access_token":"AT","token_type":"Bearer","refresh_token":"RT","expires_in":3600,"scope":"a b"}"#.utf8)
        let token = try OAuth2Flow.parseTokenResponse(json, now: now)
        #expect(token.accessToken == "AT")
        #expect(token.refreshToken == "RT")
        #expect(token.expiresAt == now.addingTimeInterval(3600))
        #expect(!token.isExpired(now: now))
        #expect(token.isExpired(now: now.addingTimeInterval(3600)))   // at expiry, past the 60s skew
    }

    @Test func parseTokenResponseRejectsMissingAccessToken() {
        #expect(throws: OAuthError.self) {
            _ = try OAuth2Flow.parseTokenResponse(Data(#"{"error":"invalid_grant"}"#.utf8))
        }
    }

    // MARK: - The gate

    @Test func destinationsAreDisabledByDefault() {
        let config = UploadersConfig()
        for id in OAuthProviderID.allCases {
            #expect(config.isConfigured(id) == false)
            #expect(config.oauthCredentials(for: id) == nil)
        }
    }

    @Test func aUserOverrideEnablesTheGate() {
        // no OAuthApps.plist in the test bundle, so builtins are empty; a user
        // override is the only path to configured here
        var config = UploadersConfig()
        config.oauthApps["Dropbox"] = OAuthAppCredentials(clientID: "cid")
        #expect(config.isConfigured(.dropbox))
        #expect(config.oauthUserOverride(for: .dropbox)?.clientID == "cid")
        #expect(config.oauthCredentials(for: .dropbox)?.clientID == "cid")   // override is used
        #expect(config.isConfigured(.googleDrive) == false)   // others stay off
        // blank/whitespace client ID does not count as configured
        config.oauthApps["Box"] = OAuthAppCredentials(clientID: "   ")
        #expect(config.isConfigured(.box) == false)
        #expect(config.oauthUserOverride(for: .box) == nil)
    }

    @Test func oauthAppsSurviveARoundTrip() throws {
        var config = UploadersConfig()
        config.oauthApps["Imgur"] = OAuthAppCredentials(clientID: "cid", clientSecret: "sec")
        let data = try JSONEncoder().encode(config)
        let restored = try JSONDecoder().decode(UploadersConfig.self, from: data)
        #expect(restored.oauthCredentials(for: .imgur)?.clientID == "cid")
    }

    // MARK: - Loopback callback parsing

    @Test func loopbackParsesCodeAndState() {
        let request = "GET /?code=4%2F0Ab&state=xyz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
        let params = LoopbackRedirect.queryParams(fromRequestLine: request)
        #expect(params["code"] == "4/0Ab")     // percent-decoded
        #expect(params["state"] == "xyz")
    }
}
