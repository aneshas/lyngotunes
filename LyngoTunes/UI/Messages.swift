import SwiftUI

/// The full-screen states that are not lyrics: first-run setup, sign in, nothing playing,
/// no lyrics, loading, something went wrong.
private struct MessageLayout<Art: View, Actions: View>: View {
    let title: String
    let text: String
    @ViewBuilder var art: () -> Art
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        // Centered when it fits, scrollable when it does not (landscape, large text).
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 18) {
                    art()
                        .padding(.bottom, 6)
                    Text(title)
                        .font(Theme.rounded(28, .heavy))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(text)
                        .font(Theme.rounded(16, .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                    actions()
                        .padding(.top, 8)
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 30)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// A symbol in a glowing disc: the art for the simple states.
private struct GlowIcon: View {
    let symbol: String
    var color: Color = Theme.amber

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 40, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 104, height: 104)
            .background(color.opacity(0.14), in: Circle())
            .overlay(Circle().strokeBorder(color.opacity(0.35), lineWidth: 1.5))
            .shadow(color: color.opacity(0.5), radius: 30)
            .accessibilityHidden(true)
    }
}

struct SetupMessage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SpotifySession.self) private var session
    @Binding var showSettings: Bool

    var body: some View {
        MessageLayout(title: "Welcome to LyngoTunes",
                      text: "Learn languages through music. Everything runs on this phone, so it needs your own keys once.") {
            Image("Lyngonaut")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .shadow(color: Theme.defaultTint.opacity(0.7), radius: 30)
                .accessibilityHidden(true)
        } actions: {
            VStack(alignment: .leading, spacing: 12) {
                step("Spotify Client ID", done: settings.hasSpotifyClientID)
                step("OpenAI API key", done: settings.hasOpenAIKey)
                step("Sign in with Spotify", done: session.isConnected)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline))

            Button("Open Settings") { showSettings = true }
                .buttonStyle(SpotlightButtonStyle())
                .padding(.top, 8)
                .accessibilityIdentifier("setup.openSettings")
        }
        .accessibilityIdentifier("screen.setup")
    }

    private func step(_ title: String, done: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(done ? AnyShapeStyle(Theme.spotlight) : AnyShapeStyle(Color.white.opacity(0.35)))
            Text(title)
                .font(Theme.rounded(16, .semibold))
                .foregroundStyle(.white.opacity(done ? 0.6 : 0.95))
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "done" : "to do")
    }
}

struct ConnectMessage: View {
    @Environment(SpotifySession.self) private var session

    var body: some View {
        MessageLayout(title: "Connect Spotify",
                      text: "LyngoTunes follows the song playing in your Spotify and shows its lyrics line by line with a translation.") {
            GlowIcon(symbol: "dot.radiowaves.left.and.right")
        } actions: {
            Button {
                Task { await session.login() }
            } label: {
                HStack(spacing: 8) {
                    if session.isLoggingIn { ProgressView().tint(.black) }
                    Text("Sign in with Spotify")
                }
            }
            .buttonStyle(SpotlightButtonStyle())
            .disabled(session.isLoggingIn)
            .accessibilityIdentifier("connect.signIn")

            if let error = session.loginError {
                Text(error)
                    .font(Theme.rounded(14, .medium))
                    .foregroundStyle(Theme.coral)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("connect.error")
            }
            Text("Spotify Premium is needed to control playback.")
                .font(Theme.rounded(13, .medium))
                .foregroundStyle(Theme.lavender.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .accessibilityIdentifier("screen.connect")
    }
}

struct NoTrackMessage: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        MessageLayout(title: "Nothing playing",
                      text: "Play a song in Spotify and come back. The lyrics appear here as soon as the music starts.") {
            GlowIcon(symbol: "radio")
        } actions: {
            Button("Open Spotify") { openURL(URL(string: "https://open.spotify.com")!) }
                .buttonStyle(SpotlightButtonStyle())
        }
        .accessibilityIdentifier("screen.noTrack")
    }
}

struct NotFoundMessage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        MessageLayout(title: "No lyrics for this one",
                      text: "We couldn't find synced lyrics for \(model.snapshot.map { "“\($0.title)”" } ?? "this song"). Try a different song.") {
            GlowIcon(symbol: "text.badge.xmark", color: Theme.lavender)
        } actions: {
            EmptyView()
        }
        .accessibilityIdentifier("screen.notFound")
    }
}

struct FailedMessage: View {
    @Environment(AppModel.self) private var model
    let message: String

    var body: some View {
        MessageLayout(title: "Couldn't load the lyrics", text: message) {
            GlowIcon(symbol: "wifi.exclamationmark", color: Theme.coral)
        } actions: {
            Button("Try again") { model.retryLyrics() }
                .buttonStyle(SpotlightButtonStyle())
        }
        .accessibilityIdentifier("screen.failed")
    }
}

struct LoadingMessage: View {
    var body: some View {
        VStack(spacing: 18) {
            VinylSpinner()
                .frame(width: 96, height: 96)
            Text("Finding the lyrics…")
                .font(Theme.rounded(16, .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("screen.loading")
    }
}

/// A spinning record, drawn in code (replaces the web app's loader GIF).
struct VinylSpinner: View {
    @State private var spinning = false

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.85))
            ForEach(0..<4) { ring in
                Circle()
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
                    .padding(CGFloat(8 + ring * 7))
            }
            // The light streak is what makes the rotation visible.
            Circle()
                .trim(from: 0.02, to: 0.16)
                .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .padding(18)
            Circle().fill(Theme.spotlight).padding(34)
            Circle().fill(Theme.stageBottom).frame(width: 6, height: 6)
        }
        .rotationEffect(.degrees(spinning ? 360 : 0))
        .shadow(color: Theme.coral.opacity(0.35), radius: 22)
        .onAppear {
            guard !Motion.reduceMotion else { return }
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { spinning = true }
        }
        .accessibilityLabel("Loading")
    }
}
