import SwiftUI

/// The floating bar at the bottom: cover, song, previous / play-pause / next, progress.
struct PlayerBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                cover
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.snapshot?.title ?? "")
                        .font(Theme.rounded(15, .bold))
                        .foregroundStyle(.white)
                    Text(model.snapshot?.artist ?? "")
                        .font(Theme.rounded(13, .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                HStack(spacing: 4) {
                    control("backward.fill", label: "Previous", id: "player.prev") { model.previous() }
                    Button { model.togglePlay() } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.85))
                            .frame(width: 46, height: 46)
                            .background(Theme.spotlight, in: Circle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(isPlaying ? "Pause" : "Play")
                    .accessibilityIdentifier("player.playPause")
                    control("forward.fill", label: "Next", id: "player.next") { model.next() }
                }
            }
            ProgressLine(fraction: fraction)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .frame(maxWidth: 640)
    }

    private var isPlaying: Bool { model.snapshot?.isPlaying == true }

    private var fraction: Double {
        guard let duration = model.snapshot?.durationMs, duration > 0 else { return 0 }
        return min(1, Double(model.progressMs) / Double(duration))
    }

    private var cover: some View {
        Group {
            if let image = model.artwork {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [model.tint, Theme.stageTop], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: 46, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .accessibilityHidden(true)
    }

    private func control(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 42, height: 46)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

private struct ProgressLine: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule().fill(Theme.spotlight)
                    .frame(width: max(3, geo.size.width * fraction))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
