import Foundation

public protocol LyricsProvider: Sendable {
    /// Synced (LRC) lyrics for a song, or nil when none exist.
    func syncedLyrics(title: String, artist: String) async throws -> String?
}

/// lrclib.net: free synced lyrics, no key.
public struct LRCLibClient: LyricsProvider {
    private let http: HTTPClient

    public init(http: HTTPClient = URLSessionHTTP()) {
        self.http = http
    }

    private struct Hit: Decodable {
        let syncedLyrics: String?
    }

    public func syncedLyrics(title: String, artist: String) async throws -> String? {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 30
        request.setValue("LyngoTunes iOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await http.send(request)
        guard response.statusCode == 200 else {
            if response.statusCode == 404 { return nil }
            throw LyricsError.http(response.statusCode)
        }
        let hits = (try? JSONDecoder().decode([Hit].self, from: data)) ?? []
        return hits.compactMap(\.syncedLyrics).first { !$0.isEmpty }
    }
}

public enum LyricsError: LocalizedError, Equatable {
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .http(let code): return "The lyrics service answered with an error (\(code))."
        }
    }
}
