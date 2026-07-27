// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE
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

    func connect(_ id: OAuthProviderID) async {
        await run(id)
    }

    private func run(_ id: OAuthProviderID) async {
        let config = UploadersConfig.load()
        guard let credentials = config.oauthCredentials(for: id) else {
            AppLog.upload.error("OAuth connect \(id.rawValue, privacy: .public): no app credentials")
            presentError(id, message: "Add a client ID before connecting.")
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
            AppLog.upload.info("OAuth connect \(id.rawValue, privacy: .public): listening on \(redirect.redirectURI, privacy: .public), opening browser")
            guard NSWorkspace.shared.open(authorizeURL) else {
                throw OAuthError.authorizationFailed("the sign-in page could not be opened in your browser")
            }

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
            AppLog.upload.info("OAuth connect \(id.rawValue, privacy: .public): connected")
            Notifier.notify(title: id.displayName, body: "Connected. \(id.displayName) is ready to use.")
        } catch is CancellationError {
            // user closed the flow — nothing to report
        } catch {
            AppLog.upload.error("OAuth connect \(id.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            presentError(id, message: error.localizedDescription)
        }
    }

    /// Connect is launched from the Settings window, so failures surface as an
    /// alert there — a notification can be silently dropped when Notification
    /// Center authorization was denied, which made a failed connect look like
    /// the button did nothing.
    private func presentError(_ id: OAuthProviderID, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(id.displayName) connection failed"
        alert.informativeText = message
        alert.runModal()
    }
}
