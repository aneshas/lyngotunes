import SwiftUI

/// "Midnight stage": a dark hall, one warm spotlight. All colors live here.
enum Theme {
    static let stageTop = Color(red: 0.11, green: 0.08, blue: 0.27)      // deep indigo
    static let stageBottom = Color(red: 0.027, green: 0.024, blue: 0.06) // almost black
    static let coral = Color(red: 1.0, green: 0.48, blue: 0.35)
    static let amber = Color(red: 1.0, green: 0.72, blue: 0.30)
    static let lavender = Color(red: 0.76, green: 0.70, blue: 1.0)
    static let defaultTint = Color(red: 0.45, green: 0.36, blue: 1.0)
    static let card = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.10)

    /// The warm accent: the line being sung, the main button.
    static let spotlight = LinearGradient(colors: [coral, amber], startPoint: .leading, endPoint: .trailing)

    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

enum Motion {
    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
}

/// The filled pill used for every main action.
struct SpotlightButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.rounded(17, .bold))
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 26)
            .padding(.vertical, 14)
            .background(Theme.spotlight, in: Capsule())
            .shadow(color: Theme.coral.opacity(0.45), radius: 16, y: 6)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
