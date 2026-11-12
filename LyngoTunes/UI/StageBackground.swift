import SwiftUI

/// The backdrop behind everything: an indigo-to-black hall with a soft glow in the color of
/// the song that is playing, and a faint warm light from the opposite corner.
struct StageBackground: View {
    var tint: Color
    @State private var drift = false

    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height)
            ZStack {
                LinearGradient(colors: [Theme.stageTop, Theme.stageBottom], startPoint: .top, endPoint: .bottom)
                Circle()
                    .fill(tint.opacity(0.55))
                    .frame(width: side * 0.9, height: side * 0.9)
                    .blur(radius: side * 0.22)
                    .offset(x: -geo.size.width * (drift ? 0.25 : 0.4), y: -geo.size.height * (drift ? 0.42 : 0.34))
                Circle()
                    .fill(Theme.coral.opacity(0.16))
                    .frame(width: side * 0.7, height: side * 0.7)
                    .blur(radius: side * 0.2)
                    .offset(x: geo.size.width * (drift ? 0.45 : 0.35), y: geo.size.height * (drift ? 0.38 : 0.48))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .onAppear {
            guard !Motion.reduceMotion else { return }
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}
