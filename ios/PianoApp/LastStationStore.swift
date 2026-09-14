//
// LastStationStore.swift — remember the most recently played station.
//
// The app restores this on launch and starts playing a song from it
// (issue #4). A station id is non-sensitive, so it lives in
// `UserDefaults` rather than the Keychain (which is for the credentials).
//
// Copyright (c) 2025 Spencer Graffunder
// MIT licensed.
//

import Foundation

/// Remembers the id of the most recently played station so the app can
/// restore and auto-play it on the next launch (issue #4).
///
/// Backed by `UserDefaults` (a station id is non-sensitive, so it does not
/// need the Keychain). The `UserDefaults` instance is injectable so unit
/// tests can run against a private suite instead of polluting the app's
/// standard domain.
struct LastStationStore {
    /// The single key used for the stored station id.
    static let key = "last-played-station-id"

    var defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Remember `stationID` (pass `nil` to forget it, e.g. on logout).
    func save(_ stationID: String?) {
        if let stationID {
            defaults.set(stationID, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }

    /// The most recently played station id, or `nil` if none is stored.
    func load() -> String? {
        defaults.string(forKey: Self.key)
    }
}
