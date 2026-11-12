import Foundation

/// Everything the app has ever fetched, in one JSON file on the device: the lyrics per song
/// and the translation per song and language. Replaces the backend's database.
public actor LyricsStore {
    public struct CachedTrack: Codable, Equatable, Sendable {
        public var title: String
        public var artist: String
        public var lrc: String
        public var sourceLang: String?
    }

    public struct CachedTranslation: Codable, Equatable, Sendable {
        public var lines: [String]
        public var alreadyInTarget: Bool
    }

    private struct Disk: Codable {
        var tracks: [String: CachedTrack] = [:]
        var translations: [String: CachedTranslation] = [:]
    }

    private let fileURL: URL?
    private var disk: Disk?

    /// Pass nil to keep everything in memory only (tests, demo mode).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    private func loaded() -> Disk {
        if let disk { return disk }
        var fresh = Disk()
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(Disk.self, from: data) {
            fresh = saved
        }
        disk = fresh
        return fresh
    }

    private func save(_ new: Disk) {
        disk = new
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(new) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func key(_ trackID: String, _ lang: String) -> String { "\(trackID)|\(lang)" }

    public func track(_ id: String) -> CachedTrack? { loaded().tracks[id] }

    public func saveTrack(id: String, title: String, artist: String, lrc: String) {
        var d = loaded()
        d.tracks[id] = CachedTrack(title: title, artist: artist, lrc: lrc, sourceLang: d.tracks[id]?.sourceLang)
        save(d)
    }

    public func translation(trackID: String, lang: String) -> CachedTranslation? {
        loaded().translations[key(trackID, lang)]
    }

    public func saveTranslation(_ translation: LyricTranslation, trackID: String, lang: String) {
        var d = loaded()
        d.translations[key(trackID, lang)] = CachedTranslation(lines: translation.lines,
                                                               alreadyInTarget: translation.alreadyInTarget)
        if !translation.sourceLang.isEmpty { d.tracks[trackID]?.sourceLang = translation.sourceLang }
        save(d)
    }

    public var trackCount: Int { loaded().tracks.count }
    public var translationCount: Int { loaded().translations.count }

    public func clear() {
        save(Disk())
    }
}
