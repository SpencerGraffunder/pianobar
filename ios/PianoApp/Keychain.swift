//
// Keychain.swift — persist the user's Pandora credentials in the iOS
// Keychain so the app can log in automatically on the next launch.
//
// Copyright (c) 2025 Spencer Graffunder
// MIT licensed.
//

import Foundation
import Security

/// Stores the (username, password) pair as a single generic-password
/// Keychain item. The Keychain encrypts it at rest and scopes it to this
/// app.
enum Keychain {
    private static let service = "net.6xq.pianobar.ios"
    private static let account = "pandora-credentials"

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Save the credentials, replacing any previously stored pair.
    /// Returns `errSecSuccess` on success; callers should check the result
    /// (a locked keychain — e.g. a freshly booted, never-unlocked
    /// simulator in CI — makes SecItemAdd fail with a non-zero status).
    @discardableResult
    static func save(username: String, password: String) -> OSStatus {
        guard let data = try? JSONSerialization.data(
            withJSONObject: ["username": username, "password": password]
        ) else { return OSStatus(-50) /* errSecInvalidArgument */ }
        var query = baseQuery()
        query[kSecValueData as String] = data
        // Available after the device is first unlocked — a music app may
        // keep playing in the background, so no biometrics are required.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemDelete(baseQuery() as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil)
    }

    /// Load the saved credentials, or nil if none are stored.
    static func load() -> (username: String, password: String)? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
              let username = obj["username"],
              let password = obj["password"]
        else { return nil }
        return (username: username, password: password)
    }

    /// Delete the stored credentials (called on logout).
    static func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
