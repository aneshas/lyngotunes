#if DEBUG
import Foundation
import LyngoCore

/// Built-in songs for demo mode (LYNGO_DEMO=1). The words were written for this app, so
/// screenshots and tests never show anyone's copyrighted lyrics.
enum DemoContent {
    struct Song {
        let id: String
        let title: String
        let artist: String
        let durationMs: Int
        let lines: [(ms: Int, original: String, english: String)]

        var lrc: String {
            lines.map { line in
                String(format: "[%02d:%05.2f] %@", line.ms / 60000, Double(line.ms % 60000) / 1000, line.original)
            }.joined(separator: "\n")
        }
    }

    static let songs: [Song] = [
        Song(id: "demo-1", title: "Luces de la ciudad", artist: "Los Lyngonautas", durationMs: 64000, lines: [
            (2000, "La ciudad despierta bajo la lluvia", "The city wakes up under the rain"),
            (6000, "Y yo camino sin mirar atrás", "And I walk without looking back"),
            (10000, "Las luces bailan sobre el asfalto", "The lights dance on the asphalt"),
            (14000, "Como estrellas que quieren hablar", "Like stars that want to talk"),
            (18000, "", ""),
            (21000, "Canta conmigo, no tengas miedo", "Sing with me, don't be afraid"),
            (25000, "Cada palabra es un nuevo hogar", "Every word is a new home"),
            (29000, "Si no la entiendes, la aprenderemos", "If you don't understand it, we'll learn it"),
            (33000, "Con esta canción, una vez más", "With this song, one more time"),
            (37000, "", ""),
            (40000, "El tren se aleja, la noche es larga", "The train pulls away, the night is long"),
            (44000, "Pero la música me va a guiar", "But the music is going to guide me"),
            (48000, "Canta conmigo, no tengas miedo", "Sing with me, don't be afraid"),
            (52000, "Cada palabra es un nuevo hogar", "Every word is a new home"),
            (56000, "Y mañana vamos a recordar", "And tomorrow we are going to remember"),
        ]),
        Song(id: "demo-2", title: "Le dernier métro", artist: "Minuit Bleu", durationMs: 46000, lines: [
            (2000, "Le dernier métro s'en va sans moi", "The last metro leaves without me"),
            (6000, "Je rentre à pied sous les lampadaires", "I walk home under the street lamps"),
            (10000, "Une chanson me tient chaud ce soir", "A song keeps me warm tonight"),
            (14000, "Et chaque mot devient une lumière", "And every word becomes a light"),
            (18000, "", ""),
            (21000, "Apprends-moi encore une phrase", "Teach me one more sentence"),
            (25000, "Avant que le jour ne revienne", "Before the day comes back"),
            (29000, "On chantera jusqu'à l'aube", "We will sing until dawn"),
            (33000, "Dans ta langue et dans la mienne", "In your language and in mine"),
        ]),
    ]

    static func song(_ id: String) -> Song? { songs.first { $0.id == id } }
}

struct DemoLyricsProvider: LyricsProvider {
    func syncedLyrics(title: String, artist: String) async throws -> String? {
        try await Task.sleep(nanoseconds: 300_000_000)
        return DemoContent.songs.first { $0.title == title }?.lrc
    }
}

struct DemoTranslator: Translating {
    let delay: Double

    func translate(lines: [String], to target: Language) async throws -> LyricTranslation {
        try await Task.sleep(nanoseconds: UInt64(max(0.3, delay) * 1_000_000_000))
        let all = DemoContent.songs.flatMap(\.lines)
        let english = lines.map { text in all.first { $0.original == text }?.english ?? text }
        return LyricTranslation(sourceLang: "es", lines: english, alreadyInTarget: false)
    }
}

/// A pretend Spotify: plays the demo songs on a clock.
@MainActor
final class DemoBackend: PlayerBackend {
    private var index = 0
    private var isPlaying: Bool
    private var base: Int
    private var since = Date()

    init(startMs: Int, paused: Bool) {
        base = startMs
        isPlaying = !paused
    }

    private var position: Int {
        base + (isPlaying ? Int(Date().timeIntervalSince(since) * 1000) : 0)
    }

    private func set(position: Int) {
        base = position
        since = Date()
    }

    func snapshot() async throws -> PlayerSnapshot? {
        if position >= DemoContent.songs[index].durationMs { try await next() }
        let song = DemoContent.songs[index]
        return PlayerSnapshot(trackID: song.id, title: song.title, artist: song.artist,
                              durationMs: song.durationMs, progressMs: position, isPlaying: isPlaying)
    }

    func play() async throws { set(position: position); isPlaying = true; since = Date() }
    func pause() async throws { set(position: position); isPlaying = false }
    func seek(toMs position: Int) async throws { set(position: position) }
    func next() async throws { index = (index + 1) % DemoContent.songs.count; set(position: 0) }
    func previous() async throws {
        index = (index + DemoContent.songs.count - 1) % DemoContent.songs.count
        set(position: 0)
    }
}
#endif
