import XCTest
@testable import LyngoCore

/// Canned network: answers each request from a closure and records what was asked.
final class FakeHTTP: HTTPClient, @unchecked Sendable {
    var requests: [URLRequest] = []
    var handler: (URLRequest) -> (Int, String)

    init(_ handler: @escaping (URLRequest) -> (Int, String)) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

func completion(_ content: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": content]]]])
    return String(data: data, encoding: .utf8)!
}

final class LRCTests: XCTestCase {
    func testParsesTimestampsAndSkipsMetadata() {
        let lines = LRC.parse("""
        [ar: Somebody]
        [00:01.50] Hola
        [00:05.00]
        [01:02.345]  Adiós amigo
        not a lyric line
        """)
        XCTAssertEqual(lines, [
            LyricLine(timeMs: 1500, text: "Hola"),
            LyricLine(timeMs: 5000, text: ""),
            LyricLine(timeMs: 62345, text: "Adiós amigo"),
        ])
    }

    func testRepeatedLineWithSeveralTimestampsIsSorted() {
        let lines = LRC.parse("[00:30.00][00:10.00] Coro\n[00:20.00] Verso")
        XCTAssertEqual(lines.map(\.timeMs), [10000, 20000, 30000])
        XCTAssertEqual(lines.map(\.text), ["Coro", "Verso", "Coro"])
    }

    func testTimestampFormats() {
        XCTAssertEqual(LRC.timestamp("00:12"), 12000)
        XCTAssertEqual(LRC.timestamp("1:00:00.5"), 3_600_500)
        XCTAssertNil(LRC.timestamp("ar: x"))
        XCTAssertNil(LRC.timestamp("length: 03:10"))
        XCTAssertNil(LRC.timestamp("offset:+10"))
    }

    func testVersesAlignTranslationsAroundGaps() {
        let lines = LRC.parse("[00:01.00] uno\n[00:02.00]\n[00:03.00] dos")
        let verses = LRC.verses(lines: lines, translations: ["one", "two"])
        XCTAssertEqual(verses.map(\.translation), ["one", "", "two"])
        XCTAssertTrue(verses[1].isGap)
        XCTAssertEqual(LRC.verses(lines: lines, translations: nil).map(\.translation), ["", "", ""])
    }

    func testCurrentIndex() {
        let verses = LRC.verses(lines: LRC.parse("[00:01.00] a\n[00:02.00] b\n[00:03.00] c"), translations: nil)
        XCTAssertNil(LRC.currentIndex(in: verses, at: 999))
        XCTAssertEqual(LRC.currentIndex(in: verses, at: 1000), 0)
        XCTAssertEqual(LRC.currentIndex(in: verses, at: 2999), 1)
        XCTAssertEqual(LRC.currentIndex(in: verses, at: 99999), 2)
        XCTAssertNil(LRC.currentIndex(in: [], at: 5))
    }
}

final class LanguageTests: XCTestCase {
    func testCodesAreUniqueAndSortedByName() {
        XCTAssertEqual(Set(Language.all.map(\.code)).count, Language.all.count)
        XCTAssertEqual(Language.all.map(\.name), Language.all.map(\.name).sorted())
        XCTAssertEqual(Language.byCode("es")?.name, "Spanish")
        XCTAssertNil(Language.byCode("xx"))
    }
}

final class LRCLibTests: XCTestCase {
    func testPicksFirstHitWithSyncedLyricsAndEncodesQuery() async throws {
        let http = FakeHTTP { _ in
            (200, #"[{"syncedLyrics":null},{"syncedLyrics":""},{"syncedLyrics":"[00:01.00] hi"}]"#)
        }
        let lrc = try await LRCLibClient(http: http).syncedLyrics(title: "Año & Luz", artist: "Ña")
        XCTAssertEqual(lrc, "[00:01.00] hi")
        let items = URLComponents(url: http.requests[0].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "track_name" }?.value, "Año & Luz")
        XCTAssertEqual(items.first { $0.name == "artist_name" }?.value, "Ña")
    }

    func testNoHitsIsNil() async throws {
        let none = try await LRCLibClient(http: FakeHTTP { _ in (200, "[]") }).syncedLyrics(title: "a", artist: "b")
        XCTAssertNil(none)
    }

    func testServerErrorThrows() async {
        do {
            _ = try await LRCLibClient(http: FakeHTTP { _ in (500, "") }).syncedLyrics(title: "a", artist: "b")
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? LyricsError, .http(500))
        }
    }
}

final class TranslatorTests: XCTestCase {
    let spanish = Language.byCode("es")!

    func testTranslatesAndSendsKeyModelAndLines() async throws {
        let http = FakeHTTP { _ in
            (200, completion(#"{"source_language":"EN","already_in_target":false,"translations":["hola","adiós"]}"#))
        }
        let result = try await OpenAITranslator(http: http, apiKey: " sk-test \n", model: "")
            .translate(lines: ["hello", "bye"], to: spanish)
        XCTAssertEqual(result, LyricTranslation(sourceLang: "en", lines: ["hola", "adiós"], alreadyInTarget: false))

        let request = http.requests[0]
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "gpt-6.1-terra", "an empty model setting falls back to the default")
        let format = body["response_format"] as! [String: Any]
        XCTAssertEqual(format["type"] as? String, "json_schema")
        let messages = body["messages"] as! [[String: String]]
        let user = try JSONSerialization.jsonObject(with: Data(messages[1]["content"]!.utf8)) as! [String: Any]
        XCTAssertEqual(user["target_language"] as? String, "Spanish")
        XCTAssertEqual(user["lines"] as? [String], ["hello", "bye"])
    }

    func testAlreadyInTargetLanguage() async throws {
        let http = FakeHTTP { _ in
            (200, completion("```json\n{\"source_language\":\"es\",\"already_in_target\":true,\"translations\":[]}\n```"))
        }
        let result = try await OpenAITranslator(http: http, apiKey: "k", model: "m").translate(lines: ["hola"], to: spanish)
        XCTAssertTrue(result.alreadyInTarget)
        XCTAssertEqual(result.lines, [])
    }

    func testLineCountMismatchThrows() async {
        let http = FakeHTTP { _ in (200, completion(#"{"source_language":"en","translations":["uno"]}"#)) }
        do {
            _ = try await OpenAITranslator(http: http, apiKey: "k", model: "m").translate(lines: ["a", "b"], to: spanish)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? TranslatorError, .lineCountMismatch(got: 1, want: 2))
        }
    }

    func testApiErrorCarriesOpenAIMessage() async {
        let http = FakeHTTP { _ in (401, #"{"error":{"message":"Incorrect API key provided"}}"#) }
        do {
            _ = try await OpenAITranslator(http: http, apiKey: "k", model: "m").translate(lines: ["a"], to: spanish)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? TranslatorError, .api(status: 401, message: "Incorrect API key provided"))
        }
    }

    func testMissingKeyNeverCallsTheNetwork() async {
        let http = FakeHTTP { _ in (200, "") }
        do {
            _ = try await OpenAITranslator(http: http, apiKey: "  ", model: "m").translate(lines: ["a"], to: spanish)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? TranslatorError, .missingKey)
        }
        XCTAssertTrue(http.requests.isEmpty)
    }
}

final class SpotifyAuthTests: XCTestCase {
    func testPKCEChallengeMatchesRFC7636Example() {
        let pkce = SpotifyAuth.PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertEqual(SpotifyAuth.PKCE.random().verifier.count, 64)
    }

    func testAuthorizeURL() {
        let pkce = SpotifyAuth.PKCE(verifier: "v")
        let url = SpotifyAuth(http: FakeHTTP { _ in (200, "") }, clientID: " abc ").authorizeURL(pkce: pkce, state: "s1")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        func value(_ n: String) -> String? { items.first { $0.name == n }?.value }
        XCTAssertEqual(url.host, "accounts.spotify.com")
        XCTAssertEqual(value("client_id"), "abc")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("redirect_uri"), "lyngotunes://callback")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("code_challenge"), pkce.challenge)
        XCTAssertEqual(value("scope"), "user-read-playback-state user-modify-playback-state")
    }

    func testCallbackParsing() throws {
        XCTAssertEqual(try SpotifyAuth.code(fromCallback: URL(string: "lyngotunes://callback?code=c1&state=s")!, expectedState: "s"), "c1")
        XCTAssertThrowsError(try SpotifyAuth.code(fromCallback: URL(string: "lyngotunes://callback?code=c1&state=x")!, expectedState: "s")) {
            XCTAssertEqual($0 as? SpotifyAuthError, .stateMismatch)
        }
        XCTAssertThrowsError(try SpotifyAuth.code(fromCallback: URL(string: "lyngotunes://callback?error=access_denied&state=s")!, expectedState: "s")) {
            XCTAssertEqual($0 as? SpotifyAuthError, .denied("access_denied"))
        }
    }

    func testExchangeSendsVerifierAndNoSecret() async throws {
        let http = FakeHTTP { _ in (200, #"{"access_token":"at","refresh_token":"rt","expires_in":3600}"#) }
        let now = Date(timeIntervalSince1970: 1000)
        let tokens = try await SpotifyAuth(http: http, clientID: "abc")
            .exchange(code: "c/1", pkce: .init(verifier: "ver"), now: now)
        XCTAssertEqual(tokens, SpotifyTokens(accessToken: "at", refreshToken: "rt", expiresAt: now.addingTimeInterval(3600)))
        let body = String(data: http.requests[0].httpBody!, encoding: .utf8)!
        XCTAssertEqual(body, "grant_type=authorization_code&code=c%2F1&redirect_uri=lyngotunes%3A%2F%2Fcallback&client_id=abc&code_verifier=ver")
        XCTAssertFalse(body.contains("secret"))
    }

    func testRefreshKeepsOldRefreshTokenWhenNotRotated() async throws {
        let http = FakeHTTP { _ in (200, #"{"access_token":"at2","expires_in":60}"#) }
        let old = SpotifyTokens(accessToken: "at", refreshToken: "rt", expiresAt: .distantPast)
        let tokens = try await SpotifyAuth(http: http, clientID: "abc").refresh(old)
        XCTAssertEqual(tokens.accessToken, "at2")
        XCTAssertEqual(tokens.refreshToken, "rt")
    }

    func testRevokedRefreshTokenMeansLoginRequired() async {
        let http = FakeHTTP { _ in (400, #"{"error":"invalid_grant","error_description":"Refresh token revoked"}"#) }
        let old = SpotifyTokens(accessToken: "at", refreshToken: "rt", expiresAt: .distantPast)
        do {
            _ = try await SpotifyAuth(http: http, clientID: "abc").refresh(old)
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? SpotifyAuthError, .loginRequired)
        }
    }

    func testNeedsRefresh() {
        let now = Date()
        XCTAssertTrue(SpotifyTokens(accessToken: "", refreshToken: "", expiresAt: now.addingTimeInterval(30)).needsRefresh(now: now))
        XCTAssertFalse(SpotifyTokens(accessToken: "", refreshToken: "", expiresAt: now.addingTimeInterval(600)).needsRefresh(now: now))
    }
}

final class SpotifyAPITests: XCTestCase {
    let playing = """
    {"is_playing":true,"progress_ms":4200,"item":{"id":"t1","name":"Canción","duration_ms":180000,
     "artists":[{"name":"Ana"},{"name":"Luis"}],
     "album":{"images":[{"url":"https://i/640","width":640},{"url":"https://i/300","width":300},{"url":"https://i/64","width":64}]}}}
    """

    func testPlayerState() async throws {
        let http = FakeHTTP { _ in (200, self.playing) }
        let snapshot = try await SpotifyAPI(http: http).playerState(token: "tok")
        XCTAssertEqual(snapshot, PlayerSnapshot(trackID: "t1", title: "Canción", artist: "Ana",
                                                artworkURL: URL(string: "https://i/300"), durationMs: 180000,
                                                progressMs: 4200, isPlaying: true))
        XCTAssertEqual(http.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer tok")
    }

    func testNothingPlayingAndNonSongsAreNil() async throws {
        let empty = try await SpotifyAPI(http: FakeHTTP { _ in (204, "") }).playerState(token: "t")
        XCTAssertNil(empty)
        let ad = try await SpotifyAPI(http: FakeHTTP { _ in (200, #"{"is_playing":true,"item":null}"#) }).playerState(token: "t")
        XCTAssertNil(ad)
    }

    func testCommandsHitTheRightEndpoints() async throws {
        let http = FakeHTTP { _ in (204, "") }
        let api = SpotifyAPI(http: http)
        try await api.play(token: "t")
        try await api.pause(token: "t")
        try await api.seek(toMs: 1500, token: "t")
        try await api.next(token: "t")
        try await api.previous(token: "t")
        XCTAssertEqual(http.requests.map { "\($0.httpMethod!) \($0.url!.path)\($0.url!.query.map { "?" + $0 } ?? "")" }, [
            "PUT /v1/me/player/play", "PUT /v1/me/player/pause", "PUT /v1/me/player/seek?position_ms=1500",
            "POST /v1/me/player/next", "POST /v1/me/player/previous",
        ])
    }

    func testErrorMapping() async {
        for (status, expected) in [(401, SpotifyError.unauthorized), (403, .premiumRequired),
                                   (404, .noActiveDevice), (429, .rateLimited), (502, .http(502))] {
            do {
                try await SpotifyAPI(http: FakeHTTP { _ in (status, "") }).play(token: "t")
                XCTFail("expected an error")
            } catch {
                XCTAssertEqual(error as? SpotifyError, expected)
            }
        }
    }
}

final class CountingProvider: LyricsProvider, @unchecked Sendable {
    var calls = 0
    var lrc: String?
    init(lrc: String?) { self.lrc = lrc }
    func syncedLyrics(title: String, artist: String) async throws -> String? {
        calls += 1
        try await Task.sleep(nanoseconds: 20_000_000)
        return lrc
    }
}

final class CountingTranslator: Translating, @unchecked Sendable {
    var calls = 0
    var failFirstWithMismatch = false
    func translate(lines: [String], to target: Language) async throws -> LyricTranslation {
        calls += 1
        try await Task.sleep(nanoseconds: 20_000_000)
        if failFirstWithMismatch && calls == 1 { throw TranslatorError.lineCountMismatch(got: 0, want: lines.count) }
        return LyricTranslation(sourceLang: "es", lines: lines.map { "\(target.code):\($0)" }, alreadyInTarget: false)
    }
}

final class LyricsServiceTests: XCTestCase {
    let lrc = "[00:01.00] uno\n[00:02.00]\n[00:03.00] dos"
    let english = Language.byCode("en")!

    func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("lyngo-\(UUID().uuidString)/store.json")
    }

    func testLyricsAreFetchedOnceAndSurviveARestart() async throws {
        let file = tempFile()
        let provider = CountingProvider(lrc: lrc)
        let service = LyricsService(provider: provider, store: LyricsStore(fileURL: file))
        async let first = service.lines(trackID: "t", title: "a", artist: "b")
        async let second = service.lines(trackID: "t", title: "a", artist: "b")
        let (a, b) = try await (first, second)
        XCTAssertEqual(a?.count, 3)
        XCTAssertEqual(a, b)
        XCTAssertEqual(provider.calls, 1, "concurrent requests share one fetch")

        let offline = LyricsService(provider: CountingProvider(lrc: nil), store: LyricsStore(fileURL: file))
        let again = try await offline.lines(trackID: "t", title: "a", artist: "b")
        XCTAssertEqual(again, a, "a new launch reads the lyrics from disk")
    }

    func testNotFoundIsNilAndNotCached() async throws {
        let provider = CountingProvider(lrc: nil)
        let service = LyricsService(provider: provider, store: LyricsStore(fileURL: nil))
        let none = try await service.lines(trackID: "t", title: "a", artist: "b")
        XCTAssertNil(none)
        provider.lrc = lrc
        let found = try await service.lines(trackID: "t", title: "a", artist: "b")
        XCTAssertNotNil(found)
    }

    func testTranslationIsMadeOncePerLanguageAndCached() async throws {
        let file = tempFile()
        let store = LyricsStore(fileURL: file)
        let service = LyricsService(provider: CountingProvider(lrc: lrc), store: store)
        let lines = try await service.lines(trackID: "t", title: "a", artist: "b")!
        let translator = CountingTranslator()

        async let first = service.translation(trackID: "t", lines: lines, target: english, translator: translator)
        async let second = service.translation(trackID: "t", lines: lines, target: english, translator: translator)
        let (a, b) = try await (first, second)
        XCTAssertEqual(a.lines, ["en:uno", "en:dos"], "gaps are not sent to the translator")
        XCTAssertEqual(a, b)
        XCTAssertEqual(translator.calls, 1)

        _ = try await service.translation(trackID: "t", lines: lines, target: Language.byCode("de")!, translator: translator)
        XCTAssertEqual(translator.calls, 2, "another language is another translation")

        let relaunched = LyricsService(provider: CountingProvider(lrc: nil), store: LyricsStore(fileURL: file))
        let cached = await relaunched.cachedTranslation(trackID: "t", lang: "en")
        XCTAssertEqual(cached?.lines, ["en:uno", "en:dos"])
        let source = await LyricsStore(fileURL: file).track("t")?.sourceLang
        XCTAssertEqual(source, "es")
    }

    func testLineCountMismatchIsRetriedOnce() async throws {
        let service = LyricsService(provider: CountingProvider(lrc: lrc), store: LyricsStore(fileURL: nil))
        let lines = try await service.lines(trackID: "t", title: "a", artist: "b")!
        let translator = CountingTranslator()
        translator.failFirstWithMismatch = true
        let result = try await service.translation(trackID: "t", lines: lines, target: english, translator: translator)
        XCTAssertEqual(result.lines.count, 2)
        XCTAssertEqual(translator.calls, 2)
    }

    func testClearCacheForgetsEverything() async throws {
        let provider = CountingProvider(lrc: lrc)
        let service = LyricsService(provider: provider, store: LyricsStore(fileURL: tempFile()))
        _ = try await service.lines(trackID: "t", title: "a", artist: "b")
        let before = await service.cachedSongCount()
        XCTAssertEqual(before, 1)
        await service.clearCache()
        let after = await service.cachedSongCount()
        XCTAssertEqual(after, 0)
        _ = try await service.lines(trackID: "t", title: "a", artist: "b")
        XCTAssertEqual(provider.calls, 2)
    }
}
