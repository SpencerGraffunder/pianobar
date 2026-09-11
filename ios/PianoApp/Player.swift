//
// Player.swift — audio playback of Pandora stream URLs via AVPlayer.
// (The original pianobar shells out to ffplay; on iOS we stream the
// song's audioUrl directly — both AAC+ and MP3, which AVPlayer handles.)
//
// Copyright (c) 2025 Spencer Graffunder
// MIT licensed.
//

import AVFoundation
import Foundation

/// Minimal AVPlayer wrapper with a small observable state.
final class Player: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published var volume: Float = 0.8

    private var player: AVPlayer?

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func play(url: URL) {
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.volume = volume
        player = newPlayer
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
        isPlaying = false
    }

    /// Update system player volume (called from the UI slider).
    func setVolume(_ v: Float) {
        volume = v
        player?.volume = v
    }
}
