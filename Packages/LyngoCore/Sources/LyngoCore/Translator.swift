import Foundation

public struct LyricTranslation: Equatable, Sendable {
    /// Two-letter code of the language the lyrics are written in, as detected by the translator.
    public let sourceLang: String
    /// One translated line per input line; empty when the song is already in the target language.
    public let lines: [String]
    public let alreadyInTarget: Bool

    public init(sourceLang: String, lines: [String], alreadyInTarget: Bool) {
        self.sourceLang = sourceLang
        self.lines = lines
        self.alreadyInTarget = alreadyInTarget
    }
}

public protocol Translating: Sendable {
    func translate(lines: [String], to target: Language) async throws -> LyricTranslation
}

public enum TranslatorError: LocalizedError, Equatable {
    case missingKey
    case api(status: Int, message: String)
    case badResponse
    case lineCountMismatch(got: Int, want: Int)

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Add your OpenAI API key in Settings to translate lyrics."
        case .api(let status, let message):
            return message.isEmpty ? "OpenAI answered with an error (\(status))." : "OpenAI: \(message)"
        case .badResponse:
            return "The translation came back in an unexpected format."
        case .lineCountMismatch:
            return "The translation did not line up with the lyrics."
        }
    }
}

/// Translates lyric lines through OpenAI's chat completions API with the user's own key.
public struct OpenAITranslator: Translating {
    public static let defaultModel = "gpt-6.1-terra"

    private let http: HTTPClient
    private let apiKey: String
    private let model: String

    public init(http: HTTPClient = URLSessionHTTP(), apiKey: String, model: String) {
        self.http = http
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model.isEmpty ? Self.defaultModel : model
    }

    static let instructions = """
    You are a song lyrics translator. The user sends a JSON object with "target_language" and \
    "lines", an array of lyric lines in singing order.
    Translate every line into the target language. Keep the translations gender neutral where \
    applicable. Do not translate names of people or places. Keep one translation per line, in \
    the same order: line breaks in the lyrics are meaningful, never merge or split lines.
    Answer with a JSON object and nothing else:
    {"source_language": "<two letter ISO 639-1 code of the language the lyrics are in>", \
    "already_in_target": <true if the lyrics are already in the target language>, \
    "translations": [<exactly as many strings as there are lines>]}
    If the lyrics are already in the target language, set "already_in_target" to true and \
    "translations" to an empty array.
    """

    /// Structured output: the model must answer with exactly this JSON shape.
    static let responseFormat: [String: Any] = [
        "type": "json_schema",
        "json_schema": [
            "name": "lyrics_translation",
            "strict": true,
            "schema": [
                "type": "object",
                "properties": [
                    "source_language": ["type": "string"],
                    "already_in_target": ["type": "boolean"],
                    "translations": ["type": "array", "items": ["type": "string"]],
                ],
                "required": ["source_language", "already_in_target", "translations"],
                "additionalProperties": false,
            ] as [String: Any],
        ] as [String: Any],
    ]

    public func translate(lines: [String], to target: Language) async throws -> LyricTranslation {
        guard !apiKey.isEmpty else { throw TranslatorError.missingKey }

        let payload: [String: Any] = ["target_language": target.name, "lines": lines]
        let user = String(data: try JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": Self.instructions],
                ["role": "user", "content": user],
            ],
            "response_format": Self.responseFormat,
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await http.send(request)
        guard response.statusCode == 200 else {
            throw TranslatorError.api(status: response.statusCode, message: Self.errorMessage(in: data))
        }
        return try Self.parse(completion: data, lineCount: lines.count)
    }

    private struct Completion: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct Answer: Decodable {
        let source_language: String?
        let already_in_target: Bool?
        let translations: [String]?
    }

    static func parse(completion data: Data, lineCount: Int) throws -> LyricTranslation {
        guard let completion = try? JSONDecoder().decode(Completion.self, from: data),
              let content = completion.choices.first?.message.content,
              let answer = try? JSONDecoder().decode(Answer.self, from: Data(stripFences(content).utf8))
        else { throw TranslatorError.badResponse }

        let source = (answer.source_language ?? "").lowercased()
        let lines = answer.translations ?? []
        if answer.already_in_target == true {
            return LyricTranslation(sourceLang: source, lines: [], alreadyInTarget: true)
        }
        guard lines.count == lineCount else {
            throw TranslatorError.lineCountMismatch(got: lines.count, want: lineCount)
        }
        return LyricTranslation(sourceLang: source, lines: lines, alreadyInTarget: false)
    }

    /// Some models wrap JSON in a ```json fence despite being told not to.
    static func stripFences(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("```") else { return t }
        if let firstBreak = t.firstIndex(of: "\n") { t = String(t[t.index(after: firstBreak)...]) }
        if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func errorMessage(in data: Data) -> String {
        struct Envelope: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message ?? ""
    }
}
