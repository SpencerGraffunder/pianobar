//
// KeychainTests.swift — unit tests for the credential Keychain helpers.
//
// Copyright (c) 2025 Spencer Graffunder
// MIT licensed.
//

import XCTest
@testable import PianoApp

final class KeychainTests: XCTestCase {
    private let testUser = "pb_unit_test_user"
    private let testPass = "pb_unit_test_password_123"

    /// errSecInteractionNotAllowed — the keychain refused the operation
    /// (locked / headless session). Not a bug in our code.
    private static let errSecInteractionNotAllowed: OSStatus = -34018

    /// Probe the keychain once per test process. On a headless CI runner the
    /// simulator keychain denies ALL SecItem data access with -34018 and can't
    /// be unlocked (Xcode 26 removed `simctl unlock`) — in that environment we
    /// skip. Any *other* failure is a real bug and must fail loudly. (Same
    /// pattern as PianoNetworkTests skipping when pandora.com is unreachable.)
    private static let keychainState: String = {
        let status = Keychain.save(username: "__keychain_probe__", password: "__probe__")
        Keychain.delete()
        switch status {
        case errSecSuccess:
            return "usable"
        case errSecInteractionNotAllowed:
            return "interaction-denied"
        default:
            return "unexpected-\(status)"
        }
    }()

    override func setUpWithError() throws {
        super.setUp()
        switch Self.keychainState {
        case "usable":
            break
        case "interaction-denied":
            throw XCTSkip("Keychain denies SecItem interaction in this environment (errSecInteractionNotAllowed, e.g. a headless CI runner) — the tests run for real on a normal Mac or device")
        default:
            XCTFail("Keychain probe failed with unexpected OSStatus: \(Self.keychainState)")
        }
        Keychain.delete()
    }

    override func tearDown() {
        Keychain.delete()
        super.tearDown()
    }

    /// Diagnostic: the raw SecItemCopyMatching status for our item, so a
    /// failing load() reports WHY (e.g. errSecInteractionNotAllowed =
    /// keychain locked) instead of just "nil".
    private func loadStatus() -> OSStatus {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "net.6xq.pianobar.ios",
            kSecAttrAccount as String: "pandora-credentials",
        ]
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result)
    }

    func testLoadReturnsNilWhenEmpty() {
        XCTAssertNil(Keychain.load())
    }

    func testSaveLoadRoundTrip() {
        let status = Keychain.save(username: testUser, password: testPass)
        XCTAssertEqual(status, errSecSuccess,
                       "SecItemAdd failed with OSStatus \(status) — the keychain is locked (e.g. a never-unlocked CI simulator) or unavailable")
        let saved = Keychain.load()
        if saved == nil {
            XCTFail("load() returned nil; SecItemCopyMatching status = \(loadStatus())")
        }
        XCTAssertEqual(saved?.username, testUser)
        XCTAssertEqual(saved?.password, testPass)
    }

    func testSaveReplacesPrevious() {
        XCTAssertEqual(Keychain.save(username: testUser, password: "first"), errSecSuccess)
        XCTAssertEqual(Keychain.save(username: testUser, password: testPass), errSecSuccess)
        let saved = Keychain.load()
        XCTAssertEqual(saved?.username, testUser)
        XCTAssertEqual(saved?.password, testPass)
    }

    func testDeleteRemovesCredentials() {
        XCTAssertEqual(Keychain.save(username: testUser, password: testPass), errSecSuccess)
        Keychain.delete()
        XCTAssertNil(Keychain.load())
    }

    func testUsernameWithSpecialCharacters() {
        let tricky = "user@ex ample.com"
        XCTAssertEqual(Keychain.save(username: tricky, password: "p@$$wörd — 100%"), errSecSuccess)
        let saved = Keychain.load()
        XCTAssertEqual(saved?.username, tricky)
        XCTAssertEqual(saved?.password, "p@$$wörd — 100%")
    }
}
