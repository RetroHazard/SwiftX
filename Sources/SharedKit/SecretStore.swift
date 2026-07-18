// SwiftX - screenshot capture and sharing for macOS
// Copyright (c) 2026 RetroHazard
// Licensed under GPL v3 - see /LICENSE.txt
//
// Keychain-backed storage for upload credentials (S3 secret keys, host
// passwords, API tokens, the AI API key). These used to sit in cleartext in
// the JSON config files under Application Support, readable by any process
// running as the user and swept into backups. They now live in the login
// Keychain — the same place OAuth tokens already go (see OAuthTokenStore) —
// while the JSON keeps only non-secret identifiers.
//
// Settings structs route their secret fields through here on load/save (see
// SettingsFile.saveMigratingSecrets / loadApplyingSecrets). Writes are
// best-effort: if the Keychain is unavailable (e.g. a headless CI run) the
// caller keeps the value in JSON rather than losing it.

import Foundation
import Security

public enum SecretStore {
    /// Distinct from the OAuth service string so the two never collide.
    static let service = "com.retrohazard.swiftx.secrets"

    /// Stores (or replaces) a secret. Returns true only when the Keychain
    /// actually accepted the write, so callers can decide whether it is safe to
    /// drop the plaintext copy.
    @discardableResult
    public static func set(_ value: String, for account: String) -> Bool {
        var query = baseQuery(account)
        SecItemDelete(query as CFDictionary) // upsert: delete then add
        query[kSecValueData as String] = Data(value.utf8)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    public static func get(_ account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(for account: String) {
        SecItemDelete(baseQuery(account) as CFDictionary)
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
