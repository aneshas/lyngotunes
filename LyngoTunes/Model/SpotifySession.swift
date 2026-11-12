import AuthenticationServices
import LyngoCore
import Observation
import UIKit

/// The Spotify login, done entirely on the device: system sign-in sheet, PKCE code
/// exchange, tokens in the Keychain, silent refresh.
@MainActor @Observable
final class SpotifySession {
    private(set) var tokens: SpotifyTokens? {
        didSet { Keychain.set(tokens.flatMap { try? JSONEncoder().encode($0) }, for: Self.account) }
    }
    private(set) var isLoggingIn = false
    var loginError: String?

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var refreshJob: Task<SpotifyTokens, Error>?
    @ObservationIgnored private var webSession: ASWebAuthenticationSession?
    @ObservationIgnored private let anchor = PresentationAnchor()
    private static let account = "spotify.tokens"

    init(settings: AppSettings) {
        self.settings = settings
        tokens = Keychain.data(Self.account).flatMap { try? JSONDecoder().decode(SpotifyTokens.self, from: $0) }
    }

    var isConnected: Bool { tokens != nil }

    func login() async {
        guard settings.hasSpotifyClientID, !isLoggingIn else { return }
        let auth = SpotifyAuth(clientID: settings.spotifyClientID)
        let pkce = SpotifyAuth.PKCE.random()
        let state = SpotifyAuth.randomString(length: 24)
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }
        do {
            let callback = try await authenticate(at: auth.authorizeURL(pkce: pkce, state: state))
            let code = try SpotifyAuth.code(fromCallback: callback, expectedState: state)
            tokens = try await auth.exchange(code: code, pkce: pkce)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // The user closed the sheet; nothing to report.
        } catch {
            loginError = error.localizedDescription
        }
    }

    func disconnect() {
        refreshJob?.cancel()
        refreshJob = nil
        tokens = nil
    }

    /// An access token that is good right now, refreshing it first when needed.
    func validToken() async throws -> String {
        guard let tokens else { throw SpotifyAuthError.loginRequired }
        if !tokens.needsRefresh() { return tokens.accessToken }
        return try await refreshedToken()
    }

    /// Forces a refresh (after Spotify answered 401 to a token that looked valid).
    func refreshedToken() async throws -> String {
        if let refreshJob { return try await refreshJob.value.accessToken }
        guard let current = tokens else { throw SpotifyAuthError.loginRequired }
        let auth = SpotifyAuth(clientID: settings.spotifyClientID)
        let job = Task { try await auth.refresh(current) }
        refreshJob = job
        defer { refreshJob = nil }
        do {
            let fresh = try await job.value
            tokens = fresh
            return fresh.accessToken
        } catch SpotifyAuthError.loginRequired {
            disconnect()
            throw SpotifyAuthError.loginRequired
        }
    }

    private func authenticate(at url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let completion: (URL?, Error?) -> Void = { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? SpotifyAuthError.missingCode)
                }
            }
            let session: ASWebAuthenticationSession
            if #available(iOS 17.4, *) {
                session = ASWebAuthenticationSession(url: url, callback: .customScheme(SpotifyAuth.callbackScheme),
                                                     completionHandler: completion)
            } else {
                session = ASWebAuthenticationSession(url: url, callbackURLScheme: SpotifyAuth.callbackScheme,
                                                     completionHandler: completion)
            }
            session.presentationContextProvider = anchor
            webSession = session
            if !session.start() {
                continuation.resume(throwing: SpotifyAuthError.denied("could not open the sign-in sheet"))
            }
        }
    }
}

private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first.map { UIWindow(windowScene: $0) } ?? UIWindow()
    }
}
