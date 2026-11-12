# LyngoTunes: learn languages through song lyrics (iOS)

Native SwiftUI app, a rewrite of an earlier web app (React frontend, Go backend) that is
not part of this repository. It follows the song playing in the user's Spotify, shows its
synced lyrics line by line with a translation under each line, lights up the line being
sung, and jumps the music when a line is tapped.

The project is open source (MIT). It is deliberately not on the App Store: displaying
lyrics there needs licences the project does not have. Never commit lyrics of real songs,
keys, tokens, or anyone's signing team id.

Display name `LyngoTunes`, product `LyngoTunes.app`, bundle id `io.anes.lyngotunes`,
iPhone only, iOS 17+, dark only.

**No memory for this project.** Everything a future session needs goes in this file.

## Rules (do not break these)

- **No backend, no account.** The app talks directly to Spotify, lrclib.net and OpenAI.
  Nothing is sent anywhere else. Never add a server dependency.
- **Keys come from Settings.** The Spotify Client ID and the OpenAI API key are typed in by
  the user and stored in the Keychain, with the Spotify tokens. Never hard-code a key or a
  client id, never put one in the repo, UserDefaults or logs.
- **Spotify login is Authorization Code with PKCE** (`SpotifyAuth` in core): no client
  secret exists anywhere. Redirect URI is `lyngotunes://callback`; the user must add it to
  their app in the Spotify developer dashboard. `ASWebAuthenticationSession` catches the
  redirect, so the scheme is not registered in Info.plist.
- **Everything fetched is stored locally and fetched once**: lyrics per song, translation
  per song and language (`LyricsStore`, one JSON file in Application Support). A song that
  has no lyrics is not remembered, so it is looked up again next time.
- **Lyrics show immediately, the translation arrives later.** A missing key or a failed
  translation is a banner above the lyrics, never a blocked screen.
- **The screen stays on only on the lyrics screen** (`AppModel.keepsScreenOn`,
  `isIdleTimerDisabled`); every other screen lets the phone sleep.
- **Design is "Midnight stage"**: indigo-to-black backdrop with a glow in the color of the
  song's cover, rounded heavy type, the current line white with its translation in the
  coral-to-amber gradient, other translations lavender. All colors and fonts come from
  `Theme`; do not put literal colors in views.
- Respect Reduce Motion through `Motion.reduceMotion`.

## Layout

- `Packages/LyngoCore`: pure Swift, no UI imports. `LRC` (parser, verses, current line),
  `Language` (the list of target languages), `HTTPClient` (the one seam to the network),
  `LRCLibClient`, `OpenAITranslator`, `SpotifyAuth` (PKCE, token exchange and refresh),
  `SpotifyAPI` (player state and commands), `LyricsStore`, `LyricsService` (store in front
  of the network; concurrent requests share one call).
- `LyngoTunes/App`: `AppModel` (all state: polls the player every 2 s, runs a 0.2 s clock
  in between so lines change on time, loads lyrics and translation per track),
  `DebugFlags`, the `@main` app.
- `LyngoTunes/Model`: `AppSettings` (Keychain and UserDefaults), `Keychain`,
  `SpotifySession` (login sheet, tokens, silent refresh), `PlayerBackend` (Spotify, and the
  Debug-only demo player), `Artwork` (cover and its tint), `DemoContent` (Debug only; the
  demo lyrics were written for this app, never replace them with real songs).
- `LyngoTunes/UI`: `RootView` (top bar, content switch, player bar), `LyricsView`,
  `PlayerBar`, `Messages` (setup, connect, nothing playing, no lyrics, loading, failed),
  `SettingsView`, `Theme`, `StageBackground`.
- `LyngoTunesUITests`: `DemoTests` (demo mode), `SetupTests` (real mode, Keychain).
- `Tools/render-icon.swift` draws the app icon; `Tools/sheet.swift` builds contact sheets.
- `project.yml`: XcodeGen spec. The `.xcodeproj` is generated and git-ignored.
- `Config/App.xcconfig`: bundle id and (empty) signing team; it includes the git-ignored
  `Config/Local.xcconfig`, where each developer puts their own team id and bundle id.
- `docs/screenshots`: README images, captured from demo mode on the simulator and cropped
  with `ffmpeg -vf "crop=1146:2034:0:0,scale=-2:1400"` (cuts off the Duo's right-hand strip).
- `.claude/skills/ios-app-shipping`: the workflow skill copied from the match3 project
  (project layout, headless simulator, store assets, publishing). Use it.

## How it differs from the web app

- Login needs no backend and lasts: tokens refresh silently instead of expiring after 24 h.
- The translator gets the lines as a JSON array and answers in schema-checked JSON (the backend compared
  raw line counts, which broke easily). A line-count mismatch is retried once.
- Timestamps and instrumental gaps are never sent to the translator.
- The model name is a setting. Default `gpt-6.1-terra` (set 2026-11-12: the backend's `o3-mini`
  was shut down on 2026-10-23). The request uses structured output (`json_schema`), which
  the model must support. Check OpenAI's deprecations page before changing the default.
- Play/pause really toggles; the web app's button seeked to 0.
- Podcasts and ads (no song item) count as nothing playing instead of crashing.

## Build, run, test

```sh
brew install xcodegen                  # once
xcodegen generate                      # after every project.yml or file-list change
open LyngoTunes.xcodeproj              # run the LyngoTunes scheme

cd Packages/LyngoCore && swift test    # core logic, no simulator needed
```

Swift language mode is 5 on purpose. To run on a real phone the first time: add the
redirect URI to a Spotify developer app, then enter Client ID and OpenAI key in Settings.

### Headless simulator

This machine's Xcode has no Simulator.app; the only device type the runtime supports is
the foldable iPhone Duo. Use the device named `lyngotunes-test (Claude)`, never another.

```sh
UDID=<the "lyngotunes-test (Claude)" device from: xcrun simctl list devices>
xcodebuild -project LyngoTunes.xcodeproj -scheme LyngoTunes -sdk iphonesimulator \
  -destination id=$UDID -derivedDataPath /tmp/lyngotunes-dd \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
xcrun simctl boot $UDID; xcrun simctl uninstall $UDID io.anes.lyngotunes
xcrun simctl install $UDID /tmp/lyngotunes-dd/Build/Products/Debug-iphonesimulator/LyngoTunes.app
SIMCTL_CHILD_LYNGO_DEMO=1 SIMCTL_CHILD_LYNGO_DEMO_START=20000 xcrun simctl launch $UDID io.anes.lyngotunes
xcrun simctl io $UDID screenshot --display=1 shot.png     # --display=1 is the Duo's main screen

# All tests (core + UI):
xcodebuild -project LyngoTunes.xcodeproj -scheme LyngoTunes -sdk iphonesimulator \
  -destination id=$UDID -derivedDataPath /tmp/lyngotunes-dd \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  -collect-test-diagnostics never test > ui.log 2>&1
grep -E "Test Case.*failed|error:|Executed|TEST" ui.log
```

Quirks that cost time:

- **Sign ad hoc, do not disable signing.** With `CODE_SIGNING_ALLOWED=NO` the app has no
  entitlements and every Keychain write fails with -34018, so keys are forgotten on
  relaunch and `SetupTests` fails. `CODE_SIGN_IDENTITY=-` (as above) fixes it. The Debug
  counters show the last Keychain status for exactly this.
- **Pass `-collect-test-diagnostics never`.** After a failed test xcodebuild starts
  `simctl diagnose`, which hangs for good here. If it happens: `pkill -f "simctl diagnose"`,
  kill xcodebuild, `simctl shutdown` and `boot` the device.
- Write xcodebuild output to a file and grep it afterwards; a pipe shows nothing until the
  run ends. macOS has no `timeout` command.
- The Duo's cover screen has a wide safe-area inset on the right (the clock sits there), so
  content looks pushed left in captures. Ordinary iPhones do not have it.
- Lyric lines are buttons (`app.buttons["verse.3"]`); banners and screens are found with
  `app.descendants(matching: .any)["banner.translating"]`.
- The language list is lazy: only the first dozen rows exist for a UI test.
- `sips -c` crops from the center whatever `--cropOffset` says; crop with ffmpeg.
- A sheet (Settings) spans the Duo's full width, so its right edge is lost in that crop.

### Debug flags (Debug builds only, see `DebugFlags.swift`)

`LYNGO_DEMO=1` fake player with two built-in songs, lyrics and translations (no keys, no
network, nothing written to disk); `LYNGO_STATE=setup|connect|notrack|notfound|loading|error`
forces a screen; `LYNGO_SETTINGS=1` opens Settings; `LYNGO_DEMO_START=<ms>` start position;
`LYNGO_DEMO_PAUSED=1`; `LYNGO_DEMO_TRANSLATE_SECONDS=n` slow translation (shows the
Lyngonaut banner); `LYNGO_DEMO_NO_KEY=1` demo without an OpenAI key; `LYNGO_RESET=1`
forgets keys, login and preferences at launch.

UI tests read the hidden `debug.counters` label:
`seeks N index I playing 0|1 track <id> awake 0|1 keychain <OSStatus>`.

## Not verified yet

The real Spotify login, player control and OpenAI translation have only been exercised
through unit tests with canned responses; they need the owner's Client ID and API key on a
device. The lrclib.net response format was checked against the live service.

## Not done yet

Landscape layout has not been looked at. Nothing is prepared for the App Store, on purpose
(see above); the skill's store references are unused here.
