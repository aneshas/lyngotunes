import Foundation

/// What is playing right now.
public struct PlayerSnapshot: Equatable, Sendable {
    public var trackID: String
    public var title: String
    public var artist: String
    public var artworkURL: URL?
    public var durationMs: Int
    public var progressMs: Int
    public var isPlaying: Bool

    public init(trackID: String, title: String, artist: String, artworkURL: URL? = nil,
                durationMs: Int, progressMs: Int, isPlaying: Bool) {
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.artworkURL = artworkURL
        self.durationMs = durationMs
        self.progressMs = progressMs
        self.isPlaying = isPlaying
    }
}

public enum SpotifyError: LocalizedError, Equatable {
    case unauthorized
    case premiumRequired
    case noActiveDevice
    case rateLimited
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .unauthorized: return "Spotify login expired."
        case .premiumRequired: return "Controlling playback needs Spotify Premium."
        case .noActiveDevice: return "No active Spotify device. Start a song in Spotify first."
        case .rateLimited: return "Spotify is busy. Trying again shortly."
        case .http(let code): return "Spotify answered with an error (\(code))."
        }
    }
}

/// The handful of Spotify Web API calls the app needs: read the player, steer the player.
public struct SpotifyAPI: Sendable {
    private let http: HTTPClient
    private let base = "https://api.spotify.com/v1/me/player"

    public init(http: HTTPClient = URLSessionHTTP()) {
        self.http = http
    }

    private struct PlayerResponse: Decodable {
        struct Item: Decodable {
            struct Artist: Decodable { let name: String }
            struct Album: Decodable {
                struct Image: Decodable { let url: String; let width: Int? }
                let images: [Image]?
            }
            let id: String?
            let name: String?
            let artists: [Artist]?
            let album: Album?
            let duration_ms: Int?
        }
        let item: Item?
        let progress_ms: Int?
        let is_playing: Bool?
    }

    /// Nil when nothing is playing, or when what plays is not a song (a podcast, an ad).
    public func playerState(token: String) async throws -> PlayerSnapshot? {
        let (data, response) = try await http.send(request("GET", "", token: token))
        if response.statusCode == 204 { return nil }
        try check(response)
        return Self.snapshot(from: data)
    }

    static func snapshot(from data: Data) -> PlayerSnapshot? {
        guard let body = try? JSONDecoder().decode(PlayerResponse.self, from: data),
              let item = body.item, let name = item.name, !name.isEmpty,
              let artist = item.artists?.first?.name else { return nil }
        // Prefer a mid-size cover: big enough for the bar, small enough to load fast.
        let images = item.album?.images ?? []
        let image = images.first { ($0.width ?? 0) <= 320 && ($0.width ?? 0) >= 200 } ?? images.first
        return PlayerSnapshot(
            trackID: item.id ?? "\(name)|\(artist)",
            title: name,
            artist: artist,
            artworkURL: image.flatMap { URL(string: $0.url) },
            durationMs: item.duration_ms ?? 0,
            progressMs: body.progress_ms ?? 0,
            isPlaying: body.is_playing ?? false)
    }

    public func play(token: String) async throws { try await command("PUT", "/play", token: token) }
    public func pause(token: String) async throws { try await command("PUT", "/pause", token: token) }
    public func next(token: String) async throws { try await command("POST", "/next", token: token) }
    public func previous(token: String) async throws { try await command("POST", "/previous", token: token) }
    public func seek(toMs position: Int, token: String) async throws {
        try await command("PUT", "/seek?position_ms=\(max(0, position))", token: token)
    }

    private func command(_ method: String, _ path: String, token: String) async throws {
        var req = request(method, path, token: token)
        req.httpBody = Data("{}".utf8)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await http.send(req)
        try check(response)
    }

    private func request(_ method: String, _ path: String, token: String) -> URLRequest {
        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = method
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func check(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401: throw SpotifyError.unauthorized
        case 403: throw SpotifyError.premiumRequired
        case 404: throw SpotifyError.noActiveDevice
        case 429: throw SpotifyError.rateLimited
        default: throw SpotifyError.http(response.statusCode)
        }
    }
}
