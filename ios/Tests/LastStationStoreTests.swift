//
// LastStationStoreTests.swift — unit tests for the last-played-station
// persistence helpers (issue #4). Pure UserDefaults logic: no network,
// no keychain, so these run on any simulator (a private suite, so they
// never touch the app's standard domain).
//
// Copyright (c) 2025 Spencer Graffunder
// MIT licensed.
//

import XCTest
@testable import PianoApp

final class LastStationStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: LastStationStore!

    override func setUpWithError() throws {
        super.setUp()
        let suite = "LastStationStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        store = LastStationStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removeObject(forKey: LastStationStore.key)
        defaults = nil
        store = nil
        super.tearDown()
    }

    func testLoadReturnsNilWhenEmpty() {
        XCTAssertNil(store.load())
    }

    func testSaveLoadRoundTrip() {
        store.save("S1XABC123")
        XCTAssertEqual(store.load(), "S1XABC123")
    }

    func testSaveReplacesPrevious() {
        store.save("first")
        store.save("second")
        XCTAssertEqual(store.load(), "second")
    }

    func testSaveNilForgets() {
        store.save("abc")
        store.save(nil)
        XCTAssertNil(store.load())
    }

    func testPersistsAcrossStoreInstances() {
        store.save("S1PERSIST")
        // A fresh store over the same suite reads the same value back.
        let other = LastStationStore(defaults: defaults)
        XCTAssertEqual(other.load(), "S1PERSIST")
    }
}
