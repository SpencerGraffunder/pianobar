//
// SongSaver.swift — download a Pandora stream and transcode it to .m4a
// (AAC) so it can be shared to the Music app / Files.
//
// Note on the Music app: writing directly into the Music library
// requires Apple's restricted `MPMediaLibraryAdditions` entitlement
// (only granted to licensed music apps). The supported path for a
// sideloaded app is: save a standard audio file, then let the user
// share it to Music (or Files). That's what this supports.
//
// The transcode core (`transcode`) is pure (URL → URL) and fully
// unit-testable offline.
//
// Why not AVAssetExportSession (the previous implementation)?
// Pandora serves the high-quality stream as HE-AAC (AAC+ with SBR) —
// the same codec AVPlayer decodes fine for playback (see Player.swift).
// But AVAssetExportSession cannot ingest HE-AAC: it fails with
// CoreMedia -3840 ("The operation couldn't be completed"), which is
// exactly what the Save button reported (issue #23). The
// AVAssetReader/AVAssetWriter path below *decodes* any supported
// source (HE-AAC, MP3, plain AAC, PCM) to linear PCM and re-encodes
// to AAC, so it works for every quality tier.
//
// Copyright (c) 2025 Spencer Graffunder
// MIT licensed.
//

import AVFoundation
import Foundation

enum SongSaver {
    /// Download `url` into the app's tmp dir and return the local file.
    /// `filename` is the base name (no directory).
    ///
    /// `file://` URLs are read directly (test path); everything else
    /// goes through URLSession.
    static func download(url: URL, filename: String) async throws -> URL {
        let data: Data
        if url.scheme == "file" {
            data = try Data(contentsOf: url)
        } else {
            let (file, _) = try await URLSession.shared
                .download(from: url)
            data = try Data(contentsOf: file)
        }
        let dest = URL.temporaryDirectory
            .appendingPathComponent(filename)
        try data.write(to: dest)
        return dest
    }

    /// Full pipeline: download + transcode to `.m4a`.
    /// Returns the .m4a file URL.
    static func save(url: URL, title: String) async throws -> URL {
        let base = sanitized(title).isEmpty
            ? "song" : sanitized(title)
        let raw = try await download(url: url, filename: base + ".audio")
        defer { try? FileManager.default.removeItem(at: raw) }
        let out = URL.temporaryDirectory
            .appendingPathComponent(base + ".m4a")
        if FileManager.default.fileExists(atPath: out.path) {
            try FileManager.default.removeItem(at: out)
        }
        try await transcode(input: raw, output: out)
        return out
    }

    /// Transcode `input` to `output` as AAC in an .m4a container.
    ///
    /// Decodes the source's first audio track (HE-AAC / MP3 / AAC /
    /// PCM — anything AVFoundation can decode) to 16-bit linear PCM,
    /// then re-encodes to AAC at the source's sample rate and channel
    /// count. Pure URL→URL: testable with locally generated audio.
    static func transcode(input: URL, output: URL) async throws {
        let asset = AVURLAsset(url: input)
        guard let tracks = try await asset.loadTracks(withMediaType: .audio),
              let track = tracks.first else {
            throw NSError(domain: "SongSaver", code: 4,
                          userInfo: [NSLocalizedDescriptionKey:
                               "No audio track to transcode"])
        }
        let desc = try await track.load(.format)
        guard let src = AVAudioFormat(settingsFromDescription: desc),
              src.sampleRate > 0, src.channelCount > 0 else {
            throw NSError(domain: "SongSaver", code: 5,
                          userInfo: [NSLocalizedDescriptionKey:
                               "Unsupported audio source format"])
        }

        // Decode to 16-bit linear PCM at the source's native rate/width.
        let inSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVSampleRateKey: src.sampleRate,
            AVNumberOfChannelsKey: src.channelCount,
        ]
        // Re-encode to AAC (128 kbps) in an .m4a container.
        let outSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: src.sampleRate,
            AVNumberOfChannelsKey: src.channelCount,
            AVEncoderBitRateKey: 128_000,
        ]

        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: track, settings: inSettings)
        readerOutput.alwaysCopiesSampleData = false
        reader.add(readerOutput)

        let writer = try AVAssetWriter(
            outputURL: output, fileType: .m4a)
        let writerInput = AVAssetWriterInput(
            mediaType: .audio, outputSettings: outSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        guard reader.startReading(), writer.startWriting() else {
            throw reader.error ?? writer.error
                ?? NSError(domain: "SongSaver", code: 6,
                           userInfo: [NSLocalizedDescriptionKey:
                                "Failed to start transcode"])
        }
        writer.startSession(atSourceTime: reader.currentReadTimestamp)

        while reader.status == .reading {
            guard let sample = readerOutput.copyNextSampleBuffer()
            else { break }
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 10_000_000)  // 10 ms
            }
            writerInput.append(sampleBuffer: sample)
        }
        let readerError = reader.status == .failed ? reader.error : nil
        writerInput.markAsFinished()
        await writer.finishWriting()

        if let readerError { throw readerError }
        guard writer.status == .completed else {
            throw writer.error
                ?? NSError(domain: "SongSaver", code: 7,
                           userInfo: [NSLocalizedDescriptionKey:
                                "Transcode failed (status \(writer.status.rawValue))"])
        }
        guard FileManager.default.fileExists(atPath: output.path) else {
            throw NSError(domain: "SongSaver", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "No output file"])
        }
    }

    /// "A B C" → "A-B-C"; strips path-unsafe characters.
    static func sanitized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "*", with: "-")
            .replacingOccurrences(of: "?", with: "-")
            .replacingOccurrences(of: "\"", with: "")
    }
}
