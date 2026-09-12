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

    override func setUp() {
        super.setUp()
        Keychain.delete()
    }

    override func tearDown() {
        Keychain.delete()
        super.tearDown()
    }

    func testLoadReturnsNilWhenEmpty() {
        XCTAssertNil(Keychain.load())
    }

    func testSaveLoadRoundTrip() {
        Keychain.save(username: testUser, password: testPass)
        let saved = Keychain.load()
        XCTAssertEqual(saved?.username, testUser)
        XCTAssertEqual(saved?.password, testPass)
    }

    func testSaveReplacesPrevious() {
        Keychain.save(username: testUser, password: "first")
        Keychain.save(username: testUser, password: testPass)
        let saved = Keychain.load()
        XCTAssertEqual(saved?.username, testUser)
        XCTAssertEqual(saved?.password, testPass)
    }

    func testDeleteRemovesCredentials() {
        Keychain.save(username: testUser, password: testPass)
        Keychain.delete()
        XCTAssertNil(Keychain.load())
    }

    func testUsernameWithSpecialCharacters() {
        let tricky = "user@ex ample.com"
        Keychain.save(username: tricky, password: "p@$$wörd — 100%")
        let saved = Keychain.load()
        XCTAssertEqual(saved?.username, tricky)
        XCTAssertEqual(saved?.password, "p@$$wörd — 100%")
    }
}
