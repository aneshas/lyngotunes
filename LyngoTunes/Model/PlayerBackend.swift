import Foundation
import LyngoCore

/// Whatever plays the music. The real one is the user's Spotify, steered through the Web
/// API; Debug builds also have a fake one so the app can be verified without an account.
@MainActor
protocol PlayerBackend {
    func snapshot() async throws -> PlayerSnapshot?
    func play() async throws
    func pause() async throws
    func seek(toMs position: Int) async throws
    func next() async throws
    func previous() async throws
}

@MainActor
struct SpotifyBackend: PlayerBackend {
    let session: SpotifySession
    let api = SpotifyAPI()

    /// Runs a call with a valid token; when Spotify still says 401, refreshes once and retries.
    private func call<T>(_ work: (String) async throws -> T) async throws -> T {
        let token = try await session.validToken()
        do {
            return try await work(token)
        } catch SpotifyError.unauthorized {
            return try await work(try await session.refreshedToken())
        }
    }

    func snapshot() async throws -> PlayerSnapshot? { try await call { try await api.playerState(token: $0) } }
    func play() async throws { try await call { try await api.play(token: $0) } }
    func pause() async throws { try await call { try await api.pause(token: $0) } }
    func seek(toMs position: Int) async throws { try await call { try await api.seek(toMs: position, token: $0) } }
    func next() async throws { try await call { try await api.next(token: $0) } }
    func previous() async throws { try await call { try await api.previous(token: $0) } }
}
