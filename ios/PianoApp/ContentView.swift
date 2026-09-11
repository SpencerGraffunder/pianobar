//
// ContentView.swift — one-screen, button-first pianobar UI.
// No artwork, no fancy layout: stations, next song, love/ban/tired,
// search, create station. All on one screen.
//
// Copyright (c) 2025 Spencer Graffunder
// MIT licensed.
//

import SwiftUI
import Combine

// MARK: - View model

@MainActor
final class AppModel: ObservableObject {
    // auth
    @Published var username = ""
    @Published var password = ""
    @Published var loggedIn = false

    // data
    @Published var stations: [Station] = []
    @Published var selectedStationID: String?
    @Published var currentSong: Song?
    @Published var searchText = ""
    @Published var searchResult: SearchResult?

    // ui
    @Published var status = "Enter your Pandora account to begin."
    @Published var isWorking = false

    // playback (forward Player's changes to our own objectWillChange)
    @Published private(set) var player = Player()
    private var playerCancellable: AnyCancellable?

    private var client: PianoClient?
    private var working = false

    init() {
        playerCancellable = player.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    var selectedStation: Station? {
        guard let id = selectedStationID else { return nil }
        return stations.first { $0.stableId == id }
    }

    // MARK: - Actions (each runs one C-core exchange; state stays on main)

    private func run(_ label: String, _ work: @escaping () async throws -> Void) {
        guard !working else { return }
        working = true
        isWorking = true
        status = label + "…"
        Task {
            do {
                try await work()
                status = label + " done."
            } catch {
                status = "Error: \(error.localizedDescription)"
            }
            isWorking = false
            working = false
        }
    }

    func login() {
        guard !username.isEmpty, !password.isEmpty else { return }
        run("Logging in") { [weak self] in
            guard let self else { return }
            if self.client == nil {
                self.client = try PianoClient(
                    username: self.username, password: self.password)
            }
            guard let client = self.client else { return }
            try await client.login()
            self.loggedIn = true
            try await client.getStations()
            let list = client.stations()
            self.stations = list
            if self.selectedStationID == nil, let first = list.first {
                self.selectedStationID = first.stableId
            }
        }
    }

    func refreshStations() {
        guard let client = client else { return }
        run("Loading stations") { [weak self] in
            guard let self else { return }
            try await client.getStations()
            let list = client.stations()
            self.stations = list
            if self.selectedStationID == nil, let first = list.first {
                self.selectedStationID = first.stableId
            }
        }
    }

    private func playIfAvailable(_ songs: [Song]) {
        if let url = songs.first?.audioUrl, let u = URL(string: url) {
            player.play(url: u)
        }
    }

    func nextSong() {
        guard let client = client, let station = selectedStation else {
            status = "Pick a station first."
            return
        }
        run("Next song") { [weak self] in
            guard let self else { return }
            let songs = try await client.getPlaylist(station: station)
            self.currentSong = songs.first
            self.playIfAvailable(songs)
        }
    }

    func rate(_ rating: PianoSongRating_t, label: String) {
        guard let client = client, let song = currentSong else { return }
        run(label) { [weak self] in
            guard let self else { return }
            try await client.rateSong(song, rating: rating)
            // After rating, advance to the next song (ui.c does this).
            if let station = self.selectedStation {
                let songs = try await client.getPlaylist(station: station)
                self.currentSong = songs.first
                self.playIfAvailable(songs)
            }
        }
    }

    func markTired() {
        guard let client = client, let song = currentSong else { return }
        run("Tired") { [weak self] in
            guard let self else { return }
            try await client.markTired(song)
            if let station = self.selectedStation {
                let songs = try await client.getPlaylist(station: station)
                self.currentSong = songs.first
                self.playIfAvailable(songs)
            }
        }
    }

    func togglePlayback() {
        if player.isPlaying {
            player.pause()
        } else if let url = currentSong?.audioUrl, let u = URL(string: url) {
            player.play(url: u)
        }
    }

    func doSearch() {
        guard let client = client, !searchText.isEmpty else { return }
        run("Searching") { [weak self] in
            guard let self else { return }
            self.searchResult = try await client.search(self.searchText)
        }
    }

    private func makeStation(token: String, name: String, fromArtist: Bool) {
        guard let client = client, !token.isEmpty else { return }
        run("Making station for \(name)") { [weak self] in
            guard let self else { return }
            try await client.createStation(token: token, fromArtist: fromArtist)
            try await client.getStations()
            self.stations = client.stations()
            self.searchResult = nil
        }
    }

    func makeStationFromArtist(_ artist: SearchArtist) {
        makeStation(token: artist.musicId, name: artist.name, fromArtist: true)
    }

    func makeStationFromSong(_ song: SearchSong) {
        makeStation(token: song.musicId, name: song.title, fromArtist: false)
    }

    func logout() {
        // The C core has no explicit logout; drop our session.
        client = nil
        loggedIn = false
        stations = []
        currentSong = nil
        searchResult = nil
        selectedStationID = nil
        player.stop()
        status = "Logged out."
    }
}

// MARK: - View

struct ContentView: View {
    @StateObject private var model = AppModel()
    @FocusState private var focus: Field?

    private enum Field { case username, password, search }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if !model.loggedIn {
                    loginView
                } else {
                    mainView
                }
            }
            .padding()
            .navigationTitle("pianobar")
        }
        .interactiveDismissDisabled()
    }

    // MARK: Login

    private var loginView: some View {
        VStack(spacing: 14) {
            TextField("username", text: $model.username)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .autocapitalization(.none)
                .focused($focus, equals: .username)
            SecureField("password", text: $model.password)
                .textFieldStyle(.roundedBorder)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit { model.login() }
            Button("Log in", action: model.login)
                .buttonStyle(.borderedProminent)
                .disabled(model.isWorking || model.username.isEmpty)
            Text(model.status)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Main (everything on one screen)

    private var mainView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Station picker + refresh
                HStack {
                    Picker("Station", selection: $model.selectedStationID) {
                        Text("—").tag(String?.none)
                        ForEach(model.stations) { s in
                            Text(s.name ?? s.stableId).tag(Optional(s.stableId))
                        }
                    }
                    .pickerStyle(.menu)
                    Button {
                        model.refreshStations()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }

                // Current song
                if let song = model.currentSong {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(song.title ?? "(untitled)")
                            .font(.headline)
                        Text(song.artist ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let album = song.album {
                            Text(album)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Text("No song yet — tap Next.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Transport row
                HStack(spacing: 10) {
                    Button("Next") { model.nextSong() }
                        .buttonStyle(.borderedProminent)
                    Button(model.player.isPlaying ? "Pause" : "Play") {
                        model.togglePlayback()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.currentSong == nil)
                    Button("Love") { model.rate(PIANO_RATE_LOVE, label: "Loving") }
                        .buttonStyle(.bordered)
                        .disabled(model.currentSong == nil)
                    Button("Ban") { model.rate(PIANO_RATE_BAN, label: "Banning") }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(model.currentSong == nil)
                    Button("Tired") { model.markTired() }
                        .buttonStyle(.bordered)
                        .disabled(model.currentSong == nil)
                }

                Divider()

                // Search
                TextField("search artists or songs", text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .search)
                    .submitLabel(.search)
                    .onSubmit { model.doSearch() }
                Button("Search") { model.doSearch() }
                    .buttonStyle(.bordered)
                    .disabled(model.searchText.isEmpty)

                if let result = model.searchResult {
                    VStack(alignment: .leading, spacing: 8) {
                        if !result.artists.isEmpty {
                            Text("Artists")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(result.artists) { a in
                                Button {
                                    model.makeStationFromArtist(a)
                                } label: {
                                    Text(a.name)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        if !result.songs.isEmpty {
                            Text("Songs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(result.songs) { s in
                                Button {
                                    model.makeStationFromSong(s)
                                } label: {
                                    Text("\(s.title) — \(s.artist)")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        if result.isEmpty {
                            Text("No results.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(model.status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 40)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    model.refreshStations()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                Button {
                    model.logout()
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .disabled(model.isWorking)
        .onAppear {
            if !model.loggedIn { focus = .username }
        }
    }
}

#Preview {
    ContentView()
}
