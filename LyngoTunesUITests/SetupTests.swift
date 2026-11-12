import XCTest

/// The first-run path with the real (non-demo) app: keys typed into Settings are kept in
/// the Keychain and decide which screen shows. Never reaches the network.
final class SetupTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        // Leave the simulator as a clean first run.
        let app = XCUIApplication()
        app.launchEnvironment = ["LYNGO_RESET": "1"]
        app.launch()
        app.terminate()
    }

    private func exists(_ app: XCUIApplication, _ id: String, timeout: TimeInterval = 6) -> Bool {
        app.descendants(matching: .any)[id].waitForExistence(timeout: timeout)
    }

    func testKeysEnteredInSettingsAreKeptAndUnlockTheSignIn() {
        let app = XCUIApplication()
        app.launchEnvironment = ["LYNGO_RESET": "1"]
        app.launch()
        XCTAssertTrue(exists(app, "screen.setup"), "a fresh install asks for setup")

        app.buttons["setup.openSettings"].tap()
        let clientID = app.textFields["settings.clientID"]
        XCTAssertTrue(clientID.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings.signIn"].isEnabled, "no sign-in without a Client ID")
        clientID.tap()
        clientID.typeText("0123456789abcdef0123456789abcdef")
        XCTAssertTrue(app.buttons["settings.signIn"].isEnabled)

        let key = app.secureTextFields["settings.openAIKey"]
        key.tap()
        key.typeText("sk-test-key")
        app.buttons["settings.done"].tap()
        XCTAssertTrue(exists(app, "screen.connect"), "with a Client ID the app offers the Spotify sign-in")

        let written = app.staticTexts["debug.counters"].label
        XCTAssertTrue(written.contains("keychain 0"), "the Keychain accepted the keys: \(written)")

        // A relaunch without the reset flag must still know the keys.
        app.terminate()
        app.launchEnvironment = [:]
        app.launch()
        let relaunched = exists(app, "screen.connect")
        if !relaunched { try? app.debugDescription.write(toFile: "/tmp/lyngo-dump-relaunch.txt", atomically: true, encoding: .utf8) }
        XCTAssertTrue(relaunched, "the Client ID survived a relaunch")
        app.buttons["settings.open"].tap()
        XCTAssertTrue(app.textFields["settings.clientID"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["settings.clientID"].value as? String, "0123456789abcdef0123456789abcdef")
        XCTAssertNotEqual(app.secureTextFields["settings.openAIKey"].value as? String, "sk-…", "the key field is filled")
    }

    func testLanguageChoiceShowsInTheTopBar() {
        let app = XCUIApplication()
        app.launchEnvironment = ["LYNGO_RESET": "1"]
        app.launch()
        XCTAssertTrue(app.buttons["top.language"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.buttons["top.language"].label, "Translating to English")

        app.buttons["top.language"].tap()
        XCTAssertTrue(exists(app, "settings.language"))
        app.descendants(matching: .any)["settings.language"].firstMatch.tap()
        let czech = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Czech")).firstMatch
        XCTAssertTrue(czech.waitForExistence(timeout: 5))
        czech.tap()
        app.buttons["settings.done"].tap()
        XCTAssertTrue(app.buttons["top.language"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["top.language"].label, "Translating to Czech")
    }
}
