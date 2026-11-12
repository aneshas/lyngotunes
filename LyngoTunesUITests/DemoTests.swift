import XCTest

/// Drives the app in demo mode (fake player, built-in songs): no account, no network.
final class DemoTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ environment: [String: String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["LYNGO_DEMO": "1"].merging(environment) { $1 }
        app.launch()
        return app
    }

    private func counters(_ app: XCUIApplication) -> String {
        app.staticTexts["debug.counters"].label
    }

    private func waitFor(_ app: XCUIApplication, counters fragment: String, timeout: TimeInterval = 8) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if counters(app).contains(fragment) { return true }
            usleep(200_000)
        }
        return false
    }

    func testTappingALineSeeksAndLightsIt() {
        let app = launch(["LYNGO_DEMO_PAUSED": "1"])
        let line = app.buttons["verse.2"]
        XCTAssertTrue(line.waitForExistence(timeout: 8))
        XCTAssertEqual(line.value as? String, "upcoming")
        XCTAssertTrue(line.label.contains("Las luces bailan"), line.label)
        // The translation lands a moment after the lyrics.
        expectation(for: NSPredicate(format: "label CONTAINS %@", "The lights dance"), evaluatedWith: line)
        waitForExpectations(timeout: 6)

        line.tap()
        XCTAssertTrue(waitFor(app, counters: "seeks 1 index 2"), counters(app))
        XCTAssertEqual(app.buttons["verse.2"].value as? String, "current")
        XCTAssertEqual(app.buttons["verse.0"].value as? String, "past")
        XCTAssertEqual(app.buttons["verse.3"].value as? String, "upcoming")
    }

    func testLinesAdvanceWhilePlaying() {
        let app = launch(["LYNGO_DEMO_START": "5000"])
        XCTAssertTrue(waitFor(app, counters: "index 1 playing 1"), counters(app))
        XCTAssertTrue(waitFor(app, counters: "index 2 playing 1"), "the next line lights up on time: \(counters(app))")
    }

    func testOpeningMidSongShowsTheLineBeingSung() {
        // Line 12 is far below the first screenful: it is only reachable if the app scrolled to it.
        let app = launch(["LYNGO_DEMO_START": "49000", "LYNGO_DEMO_PAUSED": "1"])
        let line = app.buttons["verse.12"]
        XCTAssertTrue(line.waitForExistence(timeout: 8))
        XCTAssertTrue(waitFor(app, counters: "index 12"), counters(app))
        sleep(1)
        XCTAssertEqual(line.value as? String, "current")
        let screen = app.windows.firstMatch.frame
        XCTAssertTrue(screen.contains(line.frame), "the current line is on screen: \(line.frame) in \(screen)")
    }

    func testPlayPauseNextAndPrevious() {
        let app = launch(["LYNGO_DEMO_START": "9000"])
        XCTAssertTrue(app.buttons["player.playPause"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitFor(app, counters: "playing 1 track demo-1"))

        app.buttons["player.playPause"].tap()
        XCTAssertTrue(waitFor(app, counters: "playing 0"), counters(app))
        app.buttons["player.playPause"].tap()
        XCTAssertTrue(waitFor(app, counters: "playing 1"), counters(app))

        app.buttons["player.next"].tap()
        XCTAssertTrue(waitFor(app, counters: "track demo-2"), counters(app))
        XCTAssertTrue(app.staticTexts["song.title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["song.title"].label, "Le dernier métro")

        // Early in a song, previous goes to the song before.
        app.buttons["player.prev"].tap()
        XCTAssertTrue(waitFor(app, counters: "track demo-1"), counters(app))
    }

    func testPreviousRestartsASongThatIsUnderWay() {
        let app = launch(["LYNGO_DEMO_START": "30000", "LYNGO_DEMO_PAUSED": "1"])
        XCTAssertTrue(waitFor(app, counters: "index 7"), counters(app))
        app.buttons["player.prev"].tap()
        XCTAssertTrue(waitFor(app, counters: "seeks 1 index -1 playing 0 track demo-1"), counters(app))
    }

    func testLyricsShowAtOnceAndTranslationArrivesLater() {
        let app = launch(["LYNGO_DEMO_PAUSED": "1", "LYNGO_DEMO_TRANSLATE_SECONDS": "4"])
        let first = app.buttons["verse.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["banner.translating"].waitForExistence(timeout: 3))
        XCTAssertFalse(first.label.contains("The city wakes"), "no translation yet: \(first.label)")

        let translated = NSPredicate(format: "label CONTAINS %@", "The city wakes")
        expectation(for: translated, evaluatedWith: first)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.descendants(matching: .any)["banner.translating"].exists)
    }

    func testScreenStaysOnOnlyOnTheLyricsScreen() {
        let app = launch(["LYNGO_DEMO_PAUSED": "1"])
        XCTAssertTrue(app.buttons["verse.0"].waitForExistence(timeout: 8))
        XCTAssertTrue(waitFor(app, counters: "awake 1"), "lyrics keep the screen on: \(counters(app))")

        let other = launch(["LYNGO_STATE": "notrack"])
        XCTAssertTrue(other.descendants(matching: .any)["screen.noTrack"].waitForExistence(timeout: 8))
        sleep(1)
        XCTAssertTrue(counters(other).contains("awake 0"), "other screens let the phone sleep: \(counters(other))")
    }

    func testWithoutAKeyTheLyricsStillShowWithAHint() {
        let app = launch(["LYNGO_DEMO_PAUSED": "1", "LYNGO_DEMO_NO_KEY": "1"])
        XCTAssertTrue(app.buttons["verse.0"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["banner.missingKey"].waitForExistence(timeout: 3))
    }
}
