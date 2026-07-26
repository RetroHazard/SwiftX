// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt
//
// Drives the interactive OAuth2 consent flow: open the authorize URL in the
// default browser, catch the loopback redirect, exchange the code for tokens,
// and store them in the Keychain. Dormant until app credentials exist (the
// bundled OAuthApps.plist or a user-supplied client ID).

import AppKit
import SharedKit
import UploadKit

@MainActor
final class OAuthConnectCoordinator {
    static let shared = OAuthConnectCoordinator()

    func connect(_ id: OAuthProviderID) {
        Task { await run(id) }
    }

    private func run(_ id: OAuthProviderID) async {
        let config = UploadersConfig.load()
        guard let credentials = config.oauthCredentials(for: id) else {
            Notifier.notify(title: id.displayName, body: "Add a client ID before connecting.")
            return
        }
        do {
            let redirect = try LoopbackRedirect()
            let provider = OAuthProvider.provider(id)
            let pkce = provider.usesPKCE ? PKCE.generate() : nil
            let state = OAuthCrypto.randomURLSafe(byteCount: 16)

            let authorizeURL = OAuth2Flow.authorizeURL(
                provider: provider, credentials: credentials,
                redirectURI: redirect.redirectURI, state: state, pkce: pkce)
            NSWorkspace.shared.open(authorizeURL)

            let params = try await redirect.waitForCallback()
            if let error = params["error"] {
                throw OAuthError.authorizationFailed(params["error_description"] ?? error)
            }
            // state check defeats CSRF / stray callbacks
            guard params["state"] == state, let code = params["code"] else {
                throw OAuthError.authorizationFailed("the browser returned an unexpected response")
            }

            let request = OAuth2Flow.tokenExchangeRequest(
                provider: provider, credentials: credentials,
                code: code, redirectURI: redirect.redirectURI, pkce: pkce)
            let (data, response) = try await UploadHTTP.data(for: request)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw OAuthError.authorizationFailed("token exchange failed: \(body.prefix(200))")
            }
            let token = try OAuth2Flow.parseTokenResponse(data)
            OAuthTokenStore.save(token, for: id)
            Notifier.notify(title: id.displayName, body: "Connected. \(id.displayName) is ready to use.")
        } catch is CancellationError {
            // user closed the flow — nothing to report
        } catch {
            Notifier.notify(title: "\(id.displayName) connection failed", body: error.localizedDescription)
        }
    }
}
