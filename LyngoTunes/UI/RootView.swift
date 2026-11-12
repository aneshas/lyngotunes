import LyngoCore
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var showSettings = DebugFlags.openSettings

    var body: some View {
        ZStack {
            StageBackground(tint: model.tint)

            VStack(spacing: 0) {
                TopBar(showSettings: $showSettings)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.snapshot != nil {
                PlayerBar()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if let notice = model.notice {
                NoticeToast(text: notice)
                    .padding(.top, 54)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            // Read by UI tests instead of guessing state from pixels.
            Text(model.debugCounters)
                .font(.system(size: 1))
                .opacity(0.01)
                .accessibilityIdentifier("debug.counters")
                .allowsHitTesting(false)
        }
        #endif
        .animation(.easeInOut(duration: 0.3), value: model.snapshot == nil)
        .sheet(isPresented: $showSettings, onDismiss: { model.refreshTranslation() }) {
            SettingsView()
        }
        .onChange(of: settings.targetLangCode) { model.refreshTranslation() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .setup:
            SetupMessage(showSettings: $showSettings)
        case .connect:
            ConnectMessage()
        case .noTrack:
            NoTrackMessage()
        case .loading:
            LoadingMessage()
        case .notFound:
            NotFoundMessage()
        case .failed(let message):
            FailedMessage(message: message)
        case .lyrics:
            LyricsView()
        }
    }
}

private struct TopBar: View {
    @Environment(AppSettings.self) private var settings
    @Binding var showSettings: Bool

    var body: some View {
        HStack(spacing: 10) {
            (Text("Lyngo").foregroundStyle(.white) + Text("Tunes").foregroundStyle(Theme.spotlight))
                .font(Theme.rounded(22, .heavy))
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button { showSettings = true } label: {
                HStack(spacing: 6) {
                    Text(settings.targetLanguage.flag)
                    Text(settings.targetLanguage.code.uppercased())
                        .font(Theme.rounded(13, .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 11)
                .frame(height: 36)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.hairline))
            }
            .accessibilityLabel("Translating to \(settings.targetLanguage.name)")
            .accessibilityIdentifier("top.language")

            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 36, height: 36)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.hairline))
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings.open")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}

private struct NoticeToast: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.circle.fill")
            .font(Theme.rounded(14, .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.coral.opacity(0.6)))
            .padding(.horizontal, 20)
            .accessibilityIdentifier("notice")
    }
}
