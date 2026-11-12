import Foundation

/// Launch-time switches for headless testing and demos. Read from the environment and only
/// honored in Debug builds, so a shipping app can never be put in demo mode.
///
///   LYNGO_DEMO=1                    fake player with two built-in songs, lyrics and translations;
///                                   no keys, no network, nothing written to disk
///   LYNGO_STATE=<name>              force a screen: setup, connect, notrack, notfound, loading, error
///   LYNGO_SETTINGS=1                open Settings at launch
///   LYNGO_DEMO_START=<ms>           demo song starts at this position
///   LYNGO_DEMO_PAUSED=1             demo song starts paused
///   LYNGO_DEMO_TRANSLATE_SECONDS=n  demo translation takes n seconds (to see the Lyngonaut banner)
///   LYNGO_DEMO_NO_KEY=1             demo behaves as if no OpenAI key was entered
///   LYNGO_RESET=1                   forget keys, Spotify login and preferences at launch (a clean first run)
enum DebugFlags {
    static var demo: Bool { flag("LYNGO_DEMO") }
    static var openSettings: Bool { flag("LYNGO_SETTINGS") }
    static var demoPaused: Bool { flag("LYNGO_DEMO_PAUSED") }
    static var demoNoKey: Bool { flag("LYNGO_DEMO_NO_KEY") }
    static var reset: Bool { flag("LYNGO_RESET") }
    static var forcedState: String? { value("LYNGO_STATE") }
    static var demoStartMs: Int { value("LYNGO_DEMO_START").flatMap(Int.init) ?? 0 }
    static var demoTranslateSeconds: Double { value("LYNGO_DEMO_TRANSLATE_SECONDS").flatMap(Double.init) ?? 0 }

    private static func flag(_ name: String) -> Bool { value(name) == "1" }

    private static func value(_ name: String) -> String? {
        #if DEBUG
        return ProcessInfo.processInfo.environment[name]
        #else
        return nil
        #endif
    }
}
