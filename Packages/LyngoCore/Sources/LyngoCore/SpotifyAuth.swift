import CryptoKit
import Foundation

/// What Spotify hands back after login. Stored in the Keychain by the app.
public struct SpotifyTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// True when the access token is expired or about to be.
    public func needsRefresh(now: Date = Date(), margin: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(now) < margin
    }
}

public enum SpotifyAuthError: LocalizedError, Equatable {
    case denied(String)
    case stateMismatch
    case missingCode
    case tokenExchange(status: Int, message: String)
    /// The refresh token was revoked or the client id changed: the user must log in again.
    case loginRequired

    public var errorDescription: String? {
        switch self {
        case .denied(let reason): return "Spotify login was not completed (\(reason))."
        case .stateMismatch, .missingCode: return "Spotify login returned an unexpected answer."
        case .tokenExchange(_, let message):
            return message.isEmpty ? "Spotify refused the login." : "Spotify: \(message)"
        case .loginRequired: return "Please sign in with Spotify again."
        }
    }
}

/// Authorization Code flow with PKCE: made for apps that cannot keep a secret, so the app
/// talks to Spotify directly with only the user's Client ID.
public struct SpotifyAuth: Sendable {
    public static let redirectURI = "lyngotunes://callback"
    public static let callbackScheme = "lyngotunes"
    public static let scopes = ["user-read-playback-state", "user-modify-playback-state"]

    public struct PKCE: Equatable, Sendable {
        public let verifier: String
        public let challenge: String

        public init(verifier: String) {
            self.verifier = verifier
            let digest = SHA256.hash(data: Data(verifier.utf8))
            self.challenge = Data(digest).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

        public static func random() -> PKCE {
            PKCE(verifier: randomString(length: 64))
        }
    }

    public static func randomString(length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    private let http: HTTPClient
    private let clientID: String

    public init(http: HTTPClient = URLSessionHTTP(), clientID: String) {
        self.http = http
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func authorizeURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
        ]
        return components.url!
    }

    /// Pulls the authorization code out of the redirect Spotify sent the user back with.
    public static func code(fromCallback url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") { throw SpotifyAuthError.denied(error) }
        guard value("state") == expectedState else { throw SpotifyAuthError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw SpotifyAuthError.missingCode }
        return code
    }

    public func exchange(code: String, pkce: PKCE, now: Date = Date()) async throws -> SpotifyTokens {
        try await token(fields: [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", Self.redirectURI),
            ("client_id", clientID),
            ("code_verifier", pkce.verifier),
        ], previousRefreshToken: nil, now: now)
    }

    public func refresh(_ tokens: SpotifyTokens, now: Date = Date()) async throws -> SpotifyTokens {
        do {
            return try await token(fields: [
                ("grant_type", "refresh_token"),
                ("refresh_token", tokens.refreshToken),
                ("client_id", clientID),
            ], previousRefreshToken: tokens.refreshToken, now: now)
        } catch SpotifyAuthError.tokenExchange(let status, _) where status == 400 || status == 401 {
            throw SpotifyAuthError.loginRequired
        }
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Double
    }

    private struct TokenFailure: Decodable {
        let error: String?
        let error_description: String?
    }

    private func token(fields: [(String, String)], previousRefreshToken: String?, now: Date) async throws -> SpotifyTokens {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded(fields)

        let (data, response) = try await http.send(request)
        guard response.statusCode == 200, let body = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            let failure = try? JSONDecoder().decode(TokenFailure.self, from: data)
            throw SpotifyAuthError.tokenExchange(
                status: response.statusCode,
                message: failure?.error_description ?? failure?.error ?? "")
        }
        // Spotify may or may not rotate the refresh token; keep the old one when it does not.
        guard let refresh = body.refresh_token ?? previousRefreshToken else {
            throw SpotifyAuthError.tokenExchange(status: 200, message: "no refresh token")
        }
        return SpotifyTokens(accessToken: body.access_token, refreshToken: refresh,
                             expiresAt: now.addingTimeInterval(body.expires_in))
    }
}
