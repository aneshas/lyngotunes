import LyngoCore
import Observation
import SwiftUI
import UIKit

/// The whole app's state: what Spotify plays, the lyrics for it, and where in them we are.
/// Polls the player every two seconds and runs its own clock in between so the current
/// line moves on time.
@MainActor @Observable
final class AppModel {
    /// Which screen the main area shows.
    enum Content: Equatable {
        case setup, connect, noTrack, loading, notFound, lyrics
        case failed(String)
    }

    enum LyricsState: Equatable {
        case idle, loading, notFound, ready
        case failed(String)
    }

    enum TranslationState: Equatable {
        case idle, working, done, sameLanguage, missingKey
        case failed(String)
    }

    let settings: AppSettings
    let session: SpotifySession

    private(set) var snapshot: PlayerSnapshot?
    private(set) var progressMs = 0
    private(set) var verses: [Verse] = []
    private(set) var currentIndex: Int?
    private(set) var lyricsState: LyricsState = .idle
    private(set) var translation: TranslationState = .idle
    private(set) var artwork: UIImage?
    private(set) var tint: Color = Theme.defaultTint
    private(set) var cachedSongs = 0
    /// A short message about a failed command ("needs Premium"); clears itself.
    private(set) var notice: String?
    /// Debug counters for UI tests.
    private(set) var seekCount = 0

    @ObservationIgnored private let service: LyricsService
    @ObservationIgnored private let backend: PlayerBackend
    @ObservationIgnored private let isDemo: Bool
    @ObservationIgnored private let forcedContent: Content?
    @ObservationIgnored private var lines: [LyricLine] = []
    @ObservationIgnored private var translatedLang: String?
    @ObservationIgnored private var baseProgress = 0
    @ObservationIgnored private var baseDate = Date()
    @ObservationIgnored private var holdPollsUntil = Date.distantPast
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var lyricsTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    init() {
        if DebugFlags.reset {
            for account in ["spotify.clientID", "openai.key", "spotify.tokens"] { Keychain.set(nil, for: account) }
            for key in ["openAIModel", "targetLang"] { UserDefaults.standard.removeObject(forKey: key) }
        }
        let settings = AppSettings()
        self.settings = settings
        self.session = SpotifySession(settings: settings)

        var demo = false
        #if DEBUG
        demo = DebugFlags.demo
        #endif
        isDemo = demo
        forcedContent = Self.forcedContent(DebugFlags.forcedState)

        #if DEBUG
        if demo {
            backend = DemoBackend(startMs: DebugFlags.demoStartMs, paused: DebugFlags.demoPaused)
            service = LyricsService(provider: DemoLyricsProvider(), store: LyricsStore(fileURL: nil))
            return
        }
        #endif
        backend = SpotifyBackend(session: session)
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        service = LyricsService(provider: LRCLibClient(),
                                store: LyricsStore(fileURL: folder.appendingPathComponent("lyrics.json")))
    }

    private static func forcedContent(_ name: String?) -> Content? {
        switch name {
        case "setup": return .setup
        case "connect": return .connect
        case "notrack": return .noTrack
        case "notfound": return .notFound
        case "loading": return .loading
        case "error": return .failed("The Internet connection appears to be offline.")
        default: return nil
        }
    }

    // MARK: What to show

    var content: Content {
        if let forcedContent { return forcedContent }
        if !isDemo {
            if !settings.hasSpotifyClientID { return .setup }
            if !session.isConnected { return .connect }
        }
        guard snapshot != nil else { return hasPolledOnce ? .noTrack : .loading }
        switch lyricsState {
        case .idle, .loading: return .loading
        case .notFound: return .notFound
        case .ready: return .lyrics
        case .failed(let message): return .failed(message)
        }
    }

    /// False until Spotify answered once, so the app does not flash "nothing playing" at launch.
    private(set) var hasPolledOnce = false

    var canPlay: Bool { isDemo || (settings.hasSpotifyClientID && session.isConnected) }

    var debugCounters: String {
        "seeks \(seekCount) index \(currentIndex ?? -1) playing \(snapshot?.isPlaying == true ? 1 : 0) track \(snapshot?.trackID ?? "-") awake \(keepsScreenOn ? 1 : 0) keychain \(Keychain.lastWriteStatus)"
    }

    // MARK: Lifecycle

    /// True while the phone is kept from dimming and locking: on the lyrics screen only.
    /// Lyrics are read, not touched, so without this the screen would go dark mid-song.
    private(set) var keepsScreenOn = false
    @ObservationIgnored private var isActive = false

    private func updateKeepAwake() {
        let wanted = isActive && content == .lyrics
        guard wanted != keepsScreenOn else { return }
        keepsScreenOn = wanted
        UIApplication.shared.isIdleTimerDisabled = wanted
    }

    func setActive(_ active: Bool) {
        isActive = active
        updateKeepAwake()
        pollTask?.cancel()
        tickTask?.cancel()
        guard active else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        Task { await refreshCacheCount() }
    }

    private func poll() async {
        guard canPlay, forcedContent == nil else {
            if snapshot != nil { apply(nil) }
            return
        }
        do {
            let fresh = try await backend.snapshot()
            guard canPlay else { return }
            if !hasPolledOnce { hasPolledOnce = true }
            apply(fresh)
        } catch SpotifyAuthError.loginRequired {
            apply(nil)   // the session already dropped its tokens; the connect screen shows
        } catch {
            // A dropped connection or a busy Spotify: keep what we have and ask again in two seconds.
        }
    }

    private func apply(_ fresh: PlayerSnapshot?) {
        let changedTrack = fresh?.trackID != snapshot?.trackID
        // Right after a seek or skip Spotify still reports the old position for a moment.
        if !changedTrack, Date() < holdPollsUntil, let fresh, var kept = snapshot {
            kept.durationMs = fresh.durationMs
            snapshot = kept
            return
        }
        if fresh != snapshot { snapshot = fresh }
        baseProgress = fresh?.progressMs ?? 0
        baseDate = Date()
        if changedTrack { trackChanged() }
        tick()
    }

    private func tick() {
        updateKeepAwake()
        guard let snapshot else {
            if progressMs != 0 { progressMs = 0 }
            if currentIndex != nil { currentIndex = nil }
            return
        }
        var position = baseProgress
        if snapshot.isPlaying { position += Int(Date().timeIntervalSince(baseDate) * 1000) }
        if snapshot.durationMs > 0 { position = min(position, snapshot.durationMs) }
        if position != progressMs { progressMs = position }
        let index = LRC.currentIndex(in: verses, at: position)
        if index != currentIndex { currentIndex = index }
    }

    // MARK: Lyrics

    private func trackChanged() {
        lyricsTask?.cancel()
        verses = []
        lines = []
        currentIndex = nil
        translation = .idle
        translatedLang = nil
        artwork = nil
        guard let track = snapshot else {
            lyricsState = .idle
            tint = Theme.defaultTint
            return
        }
        tint = Artwork.fallbackTint(for: track.trackID)
        lyricsState = .loading
        Task { [weak self] in await self?.loadArtwork(for: track) }
        lyricsTask = Task { [weak self] in await self?.loadLyrics(for: track) }
    }

    private func loadArtwork(for track: PlayerSnapshot) async {
        guard let url = track.artworkURL, let image = await Artwork.load(url) else { return }
        guard snapshot?.trackID == track.trackID else { return }
        artwork = image
        if let color = Artwork.tint(of: image) {
            withAnimation(.easeInOut(duration: 1.2)) { tint = color }
        }
    }

    private func loadLyrics(for track: PlayerSnapshot) async {
        do {
            let found = try await service.lines(trackID: track.trackID, title: track.title, artist: track.artist)
            guard snapshot?.trackID == track.trackID, !Task.isCancelled else { return }
            guard let found else {
                lyricsState = .notFound
                return
            }
            lines = found
            verses = LRC.verses(lines: found, translations: nil)
            lyricsState = .ready
            tick()
            await refreshCacheCount()
            await translate(track: track)
        } catch {
            guard snapshot?.trackID == track.trackID, !Task.isCancelled else { return }
            lyricsState = .failed(error.localizedDescription)
        }
    }

    private func translate(track: PlayerSnapshot) async {
        let target = settings.targetLanguage
        func stillCurrent() -> Bool {
            snapshot?.trackID == track.trackID && settings.targetLangCode == target.code && !Task.isCancelled
        }
        func show(_ result: LyricsStore.CachedTranslation) {
            verses = LRC.verses(lines: lines, translations: result.alreadyInTarget ? nil : result.lines)
            translation = result.alreadyInTarget ? .sameLanguage : .done
            translatedLang = target.code
        }

        if let cached = await service.cachedTranslation(trackID: track.trackID, lang: target.code) {
            if stillCurrent() { show(cached) }
            return
        }
        guard let translator = makeTranslator() else {
            verses = LRC.verses(lines: lines, translations: nil)
            translation = .missingKey
            return
        }
        verses = LRC.verses(lines: lines, translations: nil)
        translation = .working
        do {
            let result = try await service.translation(trackID: track.trackID, lines: lines,
                                                       target: target, translator: translator)
            if stillCurrent() { show(result) }
        } catch {
            if stillCurrent() { translation = .failed(error.localizedDescription) }
        }
    }

    private func makeTranslator() -> Translating? {
        #if DEBUG
        if isDemo {
            return DebugFlags.demoNoKey ? nil : DemoTranslator(delay: DebugFlags.demoTranslateSeconds)
        }
        #endif
        guard settings.hasOpenAIKey else { return nil }
        return OpenAITranslator(apiKey: settings.openAIKey, model: settings.openAIModel)
    }

    /// Called when Settings closes or the language changes: translate again if something
    /// that matters changed (another language, a key that was missing, a failed attempt).
    func refreshTranslation() {
        guard let track = snapshot, lyricsState == .ready else { return }
        let needsIt: Bool
        switch translation {
        case .working: needsIt = false
        case .done, .sameLanguage: needsIt = translatedLang != settings.targetLangCode
        case .idle, .missingKey, .failed: needsIt = true
        }
        guard needsIt else { return }
        lyricsTask?.cancel()
        lyricsTask = Task { [weak self] in await self?.translate(track: track) }
    }

    func retryLyrics() {
        guard snapshot != nil else { return }
        trackChanged()
    }

    func clearCache() async {
        await service.clearCache()
        await refreshCacheCount()
    }

    private func refreshCacheCount() async {
        cachedSongs = await service.cachedSongCount()
    }

    // MARK: Player controls

    func togglePlay() {
        guard var current = snapshot else { return }
        let wasPlaying = current.isPlaying
        baseProgress = progressMs
        baseDate = Date()
        current.isPlaying.toggle()
        snapshot = current
        command { wasPlaying ? try await $0.pause() : try await $0.play() }
    }

    func seek(toMs position: Int) {
        guard snapshot != nil else { return }
        seekCount += 1
        baseProgress = position
        baseDate = Date()
        tick()
        command { try await $0.seek(toMs: position) }
    }

    func next() {
        command(thenPoll: true) { try await $0.next() }
    }

    /// Like every music player: back to the start of the song first, the previous song when already there.
    func previous() {
        if progressMs > 4000 {
            seek(toMs: 0)
        } else {
            command(thenPoll: true) { try await $0.previous() }
        }
    }

    private func command(thenPoll: Bool = false, _ work: @escaping (PlayerBackend) async throws -> Void) {
        holdPollsUntil = Date().addingTimeInterval(1.2)
        Task {
            do {
                try await work(backend)
                if thenPoll {
                    holdPollsUntil = .distantPast
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    await poll()
                }
            } catch {
                holdPollsUntil = .distantPast
                show(notice: error.localizedDescription)
                await poll()
            }
        }
    }

    private func show(notice text: String) {
        noticeTask?.cancel()
        withAnimation { notice = text }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { self?.notice = nil }
        }
    }
}
