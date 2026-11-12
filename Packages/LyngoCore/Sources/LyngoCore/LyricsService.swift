import Foundation

/// Lyrics and translations with the store in front: every song is fetched once and every
/// song/language pair is translated once. Concurrent requests for the same thing share one
/// network call (the job the backend's queue and advisory lock did).
public actor LyricsService {
    private let provider: LyricsProvider
    private let store: LyricsStore
    private var lyricJobs: [String: Task<[LyricLine]?, Error>] = [:]
    private var translationJobs: [String: Task<LyricsStore.CachedTranslation, Error>] = [:]

    public init(provider: LyricsProvider, store: LyricsStore) {
        self.provider = provider
        self.store = store
    }

    /// The song's timed lines, or nil when no synced lyrics exist for it.
    public func lines(trackID: String, title: String, artist: String) async throws -> [LyricLine]? {
        if let cached = await store.track(trackID) { return LRC.parse(cached.lrc) }
        if let running = lyricJobs[trackID] { return try await running.value }

        let provider = self.provider, store = self.store
        let job = Task<[LyricLine]?, Error> {
            guard let lrc = try await provider.syncedLyrics(title: title, artist: artist) else { return nil }
            let lines = LRC.parse(lrc)
            guard !LRC.translatable(lines).isEmpty else { return nil }
            await store.saveTrack(id: trackID, title: title, artist: artist, lrc: lrc)
            return lines
        }
        lyricJobs[trackID] = job
        defer { lyricJobs[trackID] = nil }
        return try await job.value
    }

    /// A stored translation, without touching the network.
    public func cachedTranslation(trackID: String, lang: String) async -> LyricsStore.CachedTranslation? {
        await store.translation(trackID: trackID, lang: lang)
    }

    /// The translation of `lines` into `target`, from the store or freshly made by `translator`.
    public func translation(trackID: String, lines: [LyricLine], target: Language,
                            translator: Translating) async throws -> LyricsStore.CachedTranslation {
        if let cached = await store.translation(trackID: trackID, lang: target.code) { return cached }
        let key = "\(trackID)|\(target.code)"
        if let running = translationJobs[key] { return try await running.value }

        let store = self.store
        let texts = LRC.translatable(lines)
        let job = Task<LyricsStore.CachedTranslation, Error> {
            var result: LyricTranslation
            do {
                result = try await translator.translate(lines: texts, to: target)
            } catch TranslatorError.lineCountMismatch {
                // Models occasionally merge two lines; a second try usually lines up.
                result = try await translator.translate(lines: texts, to: target)
            }
            await store.saveTranslation(result, trackID: trackID, lang: target.code)
            return LyricsStore.CachedTranslation(lines: result.lines, alreadyInTarget: result.alreadyInTarget)
        }
        translationJobs[key] = job
        defer { translationJobs[key] = nil }
        return try await job.value
    }

    public func clearCache() async {
        await store.clear()
    }

    public func cachedSongCount() async -> Int {
        await store.trackCount
    }
}
