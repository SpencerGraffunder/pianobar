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
        try await transcode(
            input: raw, output: out,
            preset: AVAssetExportPresetAppleM4A)
        return out
    }

    /// Transcode `input` to `output` using the given AVAssetExportSession
    /// preset name (e.g. `AVAssetExportPresetAppleM4A`).
    /// Pure URL→URL: testable with locally generated audio.
    static func transcode(input: URL, output: URL,
                          preset: String) async throws {
        let asset = AVURLAsset(url: input)
        guard let session = AVAssetExportSession(
            asset: asset, presetName: preset) else {
            throw NSError(domain: "SongSaver", code: 3,
                          userInfo: [NSLocalizedDescriptionKey:
                               "Unsupported export preset: \(preset)"])
        }
        session.outputURL = output
        session.outputFileType = .m4a
        await session.export()
        guard session.status == .completed else {
            throw session.error
                ?? NSError(domain: "SongSaver", code: 1,
                           userInfo: [NSLocalizedDescriptionKey:
                                "Transcode failed (status \(session.status.rawValue))"])
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
