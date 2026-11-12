import LyngoCore
import SwiftUI

/// The song: every line with its translation underneath, the line being sung lit up and
/// kept in the middle of the screen. Tap a line to jump the music there.
struct LyricsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    TranslationBanner()
                    ForEach(model.verses) { verse in
                        VerseRow(verse: verse, phase: phase(of: verse))
                            .id(verse.id)
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 220)
            }
            .scrollIndicators(.hidden)
            .mask(edgeFade)
            // `initial` so opening the app in the middle of a song lands on the line being sung;
            // the hop to the next run loop lets the lines lay out before scrolling to one.
            .onChange(of: model.currentIndex, initial: true) { old, index in
                guard let index else { return }
                DispatchQueue.main.async {
                    withAnimation(Motion.reduceMotion || old == index ? nil : .easeInOut(duration: 0.55)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
            .onChange(of: model.snapshot?.trackID) {
                proxy.scrollTo("header", anchor: .top)
            }
        }
    }

    private func phase(of verse: Verse) -> VerseRow.Phase {
        guard let current = model.currentIndex else { return .upcoming }
        return verse.id == current ? .current : (verse.id < current ? .past : .upcoming)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.snapshot?.title ?? "")
                .font(Theme.rounded(30, .heavy))
                .foregroundStyle(.white)
                .accessibilityIdentifier("song.title")
            Text(model.snapshot?.artist ?? "")
                .font(Theme.rounded(17, .semibold))
                .foregroundStyle(Theme.lavender.opacity(0.85))
        }
        .padding(.bottom, 4)
        .id("header")
    }

    /// Lines dissolve into the dark at the top and bottom instead of being cut off.
    private var edgeFade: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.05),
            .init(color: .black, location: 0.88),
            .init(color: .clear, location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}

struct VerseRow: View {
    enum Phase: String { case past, current, upcoming }

    @Environment(AppModel.self) private var model
    let verse: Verse
    let phase: Phase

    var body: some View {
        Button {
            model.seek(toMs: verse.timeMs)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                if verse.isGap {
                    Text("♪  ♪  ♪")
                        .font(Theme.rounded(20, .bold))
                        .foregroundStyle(phase == .current ? AnyShapeStyle(Theme.spotlight) : AnyShapeStyle(Color.white.opacity(0.25)))
                } else {
                    Text(verse.original)
                        .font(Theme.rounded(27, .heavy))
                        .foregroundStyle(.white.opacity(originalOpacity))
                        .shadow(color: phase == .current ? model.tint.opacity(0.9) : .clear, radius: 18)
                    if !verse.translation.isEmpty {
                        Text(verse.translation)
                            .font(Theme.rounded(19, .semibold))
                            .foregroundStyle(phase == .current
                                             ? AnyShapeStyle(Theme.spotlight)
                                             : AnyShapeStyle(Theme.lavender.opacity(phase == .past ? 0.38 : 0.75)))
                            .transition(.opacity)
                    }
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .scaleEffect(phase == .current ? 1 : 0.94, anchor: .leading)
            .animation(Motion.reduceMotion ? nil : .easeInOut(duration: 0.35), value: phase)
            .animation(.easeInOut(duration: 0.5), value: verse.translation)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(verse.isGap ? "Instrumental" : "\(verse.original). \(verse.translation)")
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(phase.rawValue)
        .accessibilityHint("Jumps the song to this line")
        .accessibilityIdentifier("verse.\(verse.id)")
    }

    private var originalOpacity: Double {
        switch phase {
        case .current: return 1
        case .upcoming: return 0.62
        case .past: return 0.3
        }
    }
}

/// What is going on with the translation, when it is not simply there.
private struct TranslationBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
        switch model.translation {
        case .working:
            banner {
                Image("Lyngonaut")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 46, height: 46)
            } text: {
                Text("Lyngonaut 🚀").font(Theme.rounded(15, .heavy)).foregroundStyle(Theme.amber)
                Text("First time this song meets \(settings.targetLanguage.name). Translating, hang on…")
                    .font(Theme.rounded(14, .medium))
                    .foregroundStyle(.white.opacity(0.8))
            } trailing: {
                ProgressView().tint(Theme.amber)
            }
            .accessibilityIdentifier("banner.translating")
        case .missingKey:
            banner {
                icon("key.fill")
            } text: {
                Text("No translation yet").font(Theme.rounded(15, .heavy)).foregroundStyle(.white)
                Text("Add your OpenAI API key in Settings to see every line in \(settings.targetLanguage.name).")
                    .font(Theme.rounded(14, .medium))
                    .foregroundStyle(.white.opacity(0.8))
            } trailing: { EmptyView() }
            .accessibilityIdentifier("banner.missingKey")
        case .failed(let message):
            banner {
                icon("exclamationmark.triangle.fill")
            } text: {
                Text("Translation failed").font(Theme.rounded(15, .heavy)).foregroundStyle(.white)
                Text(message).font(Theme.rounded(14, .medium)).foregroundStyle(.white.opacity(0.8))
            } trailing: {
                Button("Retry") { model.refreshTranslation() }
                    .font(Theme.rounded(14, .bold))
                    .foregroundStyle(Theme.amber)
            }
            .accessibilityIdentifier("banner.failed")
        case .sameLanguage:
            banner {
                Text(settings.targetLanguage.flag).font(.system(size: 28))
            } text: {
                Text("Already in \(settings.targetLanguage.name)").font(Theme.rounded(15, .heavy)).foregroundStyle(.white)
                Text("This song needs no translation. Pick another language in Settings to practice.")
                    .font(Theme.rounded(14, .medium))
                    .foregroundStyle(.white.opacity(0.8))
            } trailing: { EmptyView() }
            .accessibilityIdentifier("banner.sameLanguage")
        case .idle, .done:
            EmptyView()
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(Theme.amber)
            .frame(width: 40, height: 40)
            .background(Theme.amber.opacity(0.15), in: Circle())
    }

    private func banner(@ViewBuilder leading: () -> some View, @ViewBuilder text: () -> some View,
                        @ViewBuilder trailing: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 12) {
            leading()
            VStack(alignment: .leading, spacing: 2) { text() }
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline))
        .accessibilityElement(children: .contain)
    }
}
