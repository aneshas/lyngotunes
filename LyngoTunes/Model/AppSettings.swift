import Foundation
import LyngoCore
import Observation

/// Everything the user sets up in Settings. Keys live in the Keychain, preferences in
/// UserDefaults; there is no account and no server.
@MainActor @Observable
final class AppSettings {
    var spotifyClientID: String {
        didSet { Keychain.set(spotifyClientID.trimmed, for: "spotify.clientID") }
    }
    var openAIKey: String {
        didSet { Keychain.set(openAIKey.trimmed, for: "openai.key") }
    }
    var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel.trimmed, forKey: "openAIModel") }
    }
    var targetLangCode: String {
        didSet { UserDefaults.standard.set(targetLangCode, forKey: "targetLang") }
    }

    init() {
        spotifyClientID = Keychain.string("spotify.clientID")
        openAIKey = Keychain.string("openai.key")
        openAIModel = UserDefaults.standard.string(forKey: "openAIModel") ?? OpenAITranslator.defaultModel
        targetLangCode = UserDefaults.standard.string(forKey: "targetLang") ?? Language.fallback.code
    }

    var targetLanguage: Language { Language.byCode(targetLangCode) ?? .fallback }
    var hasSpotifyClientID: Bool { !spotifyClientID.trimmed.isEmpty }
    var hasOpenAIKey: Bool { !openAIKey.trimmed.isEmpty }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
