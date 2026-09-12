//
// Player.swift — audio playback of Pandora stream URLs via AVPlayer.
// (The original pianobar shells out to ffplay; on iOS we stream the
// song's audioUrl directly — both AAC+ and MP3, which AVPlayer handles.)
//
// Failures (ATS, expired CDN tokens, bad codec) are surfaced via `lastError`
// instead of dying silently.
//
// Copyright (c) 2025 Spencer Graffunder
// MIT licensed.
//

import AVFoundation
import Combine
import Foundation

/// Minimal AVPlayer wrapper with a small observable state.
final class Player: ObservableObject {
    @Published private(set) var isPlaying = false
    /// Set when the current item fails to load/play; cleared on a new play.
    @Published private(set) var lastError: String?
    @Published var volume: Float = 0.8

    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    init() {
        try? AVAudioSession.sharedInstance()
            .setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    /// Watch an item for load failures and end-of-stream.
    private func observe(_ item: AVPlayerItem) {
        // KVO on status catches load failures (e.g. NSURLErrorDomain -1022
        // "App Transport Security requires a secure connection", 403 from an
        // expired CDN token, unsupported codec).
        statusObservation = item.observe(\.status, options: [.new]) {
            [weak self] it, _ in
            guard let self else { return }
            if it.status == .failed {
                let err = it.error
                self.lastError = "Playback failed: " +
                    (err?.localizedDescription ?? "unknown error")
                self.isPlaying = false
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item,
            queue: .main) { [weak self] _ in
            self?.isPlaying = false
        }
    }

    func play(url: URL) {
        stop()
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.volume = volume
        player = newPlayer
        observe(item)
        lastError = nil
        newPlayer.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.pause()
        player = nil
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        isPlaying = false
    }

    // MARK: Volume

    func setVolume(_ v: Float) {
        volume = min(max(0, v), 1)
        player?.volume = volume
    }

    func nudgeVolume(_ delta: Float) {
        setVolume(volume + delta)
    }

    func resetVolume() {
        setVolume(0.8)
    }
}
