import Foundation

/// One timed line of a synced (LRC) lyric. `text` is empty for an instrumental gap.
public struct LyricLine: Equatable, Sendable {
    public let timeMs: Int
    public let text: String

    public init(timeMs: Int, text: String) {
        self.timeMs = timeMs
        self.text = text
    }
}

/// A lyric line with its translation, as shown on screen.
public struct Verse: Equatable, Identifiable, Sendable {
    public let id: Int
    public let timeMs: Int
    public let original: String
    public var translation: String

    public var isGap: Bool { original.isEmpty }

    public init(id: Int, timeMs: Int, original: String, translation: String = "") {
        self.id = id
        self.timeMs = timeMs
        self.original = original
        self.translation = translation
    }
}

public enum LRC {
    /// Parses LRC text: `[mm:ss.xx] words`. A line may carry several timestamps (repeated
    /// lines); metadata tags like `[ar: name]` are skipped. Result is sorted by time.
    public static func parse(_ text: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        for raw in text.components(separatedBy: .newlines) {
            var rest = Substring(raw.trimmingCharacters(in: .whitespaces))
            var stamps: [Int] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                guard let ms = timestamp(String(tag)) else { break }
                stamps.append(ms)
                rest = rest[rest.index(after: close)...]
            }
            guard !stamps.isEmpty else { continue }
            let words = rest.trimmingCharacters(in: .whitespaces)
            for ms in stamps { lines.append(LyricLine(timeMs: ms, text: words)) }
        }
        // Stable sort: equal timestamps keep file order.
        return lines.enumerated()
            .sorted { ($0.element.timeMs, $0.offset) < ($1.element.timeMs, $1.offset) }
            .map(\.element)
    }

    /// "01:02.50" -> 62500. Nil for anything that is not a timestamp (metadata tags).
    public static func timestamp(_ tag: String) -> Int? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var total = 0.0
        for (i, part) in parts.enumerated() {
            let isLast = i == parts.count - 1
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && ($0.isNumber || (isLast && $0 == ".")) }),
                  let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return Int((total * 1000).rounded())
    }

    /// Builds the verses for display. `translations` lines up with the non-empty lines only
    /// (gaps are never sent to the translator); nil or a short array leaves the rest untranslated.
    public static func verses(lines: [LyricLine], translations: [String]?) -> [Verse] {
        var next = 0
        return lines.enumerated().map { index, line in
            var verse = Verse(id: index, timeMs: line.timeMs, original: line.text)
            if !line.text.isEmpty {
                if let translations, next < translations.count {
                    verse.translation = translations[next].trimmingCharacters(in: .whitespaces)
                }
                next += 1
            }
            return verse
        }
    }

    /// The texts worth translating, in order.
    public static func translatable(_ lines: [LyricLine]) -> [String] {
        lines.map(\.text).filter { !$0.isEmpty }
    }

    /// Index of the verse being sung at `progressMs`: the last one that has started.
    public static func currentIndex(in verses: [Verse], at progressMs: Int) -> Int? {
        var low = 0, high = verses.count
        while low < high {
            let mid = (low + high) / 2
            if verses[mid].timeMs <= progressMs { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }
}
