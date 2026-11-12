import Foundation

/// A language lyrics can be translated into. Same list the web app offered.
public struct Language: Hashable, Identifiable, Sendable {
    public let code: String   // ISO 639-1
    public let name: String
    public let flag: String   // emoji

    public var id: String { code }

    public static let all: [Language] = [
        .init(code: "af", name: "Afrikaans", flag: "🇿🇦"),
        .init(code: "sq", name: "Albanian", flag: "🇦🇱"),
        .init(code: "hy", name: "Armenian", flag: "🇦🇲"),
        .init(code: "az", name: "Azerbaijani", flag: "🇦🇿"),
        .init(code: "be", name: "Belarusian", flag: "🇧🇾"),
        .init(code: "bg", name: "Bulgarian", flag: "🇧🇬"),
        .init(code: "zh", name: "Chinese", flag: "🇨🇳"),
        .init(code: "hr", name: "Croatian", flag: "🇭🇷"),
        .init(code: "cs", name: "Czech", flag: "🇨🇿"),
        .init(code: "da", name: "Danish", flag: "🇩🇰"),
        .init(code: "nl", name: "Dutch", flag: "🇳🇱"),
        .init(code: "en", name: "English", flag: "🇬🇧"),
        .init(code: "et", name: "Estonian", flag: "🇪🇪"),
        .init(code: "fi", name: "Finnish", flag: "🇫🇮"),
        .init(code: "fr", name: "French", flag: "🇫🇷"),
        .init(code: "de", name: "German", flag: "🇩🇪"),
        .init(code: "el", name: "Greek", flag: "🇬🇷"),
        .init(code: "hi", name: "Hindi", flag: "🇮🇳"),
        .init(code: "hu", name: "Hungarian", flag: "🇭🇺"),
        .init(code: "is", name: "Icelandic", flag: "🇮🇸"),
        .init(code: "id", name: "Indonesian", flag: "🇮🇩"),
        .init(code: "ga", name: "Irish", flag: "🇮🇪"),
        .init(code: "it", name: "Italian", flag: "🇮🇹"),
        .init(code: "ja", name: "Japanese", flag: "🇯🇵"),
        .init(code: "ko", name: "Korean", flag: "🇰🇷"),
        .init(code: "lv", name: "Latvian", flag: "🇱🇻"),
        .init(code: "lt", name: "Lithuanian", flag: "🇱🇹"),
        .init(code: "mk", name: "Macedonian", flag: "🇲🇰"),
        .init(code: "mn", name: "Mongolian", flag: "🇲🇳"),
        .init(code: "no", name: "Norwegian", flag: "🇳🇴"),
        .init(code: "fa", name: "Persian", flag: "🇮🇷"),
        .init(code: "pl", name: "Polish", flag: "🇵🇱"),
        .init(code: "pt", name: "Portuguese", flag: "🇵🇹"),
        .init(code: "ro", name: "Romanian", flag: "🇷🇴"),
        .init(code: "ru", name: "Russian", flag: "🇷🇺"),
        .init(code: "sr", name: "Serbian", flag: "🇷🇸"),
        .init(code: "sk", name: "Slovak", flag: "🇸🇰"),
        .init(code: "sl", name: "Slovenian", flag: "🇸🇮"),
        .init(code: "es", name: "Spanish", flag: "🇪🇸"),
        .init(code: "sv", name: "Swedish", flag: "🇸🇪"),
        .init(code: "vi", name: "Vietnamese", flag: "🇻🇳"),
    ]

    public static let fallback = Language(code: "en", name: "English", flag: "🇬🇧")

    public static func byCode(_ code: String) -> Language? {
        all.first { $0.code == code }
    }
}
