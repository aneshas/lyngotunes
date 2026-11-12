import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Cover art and the stage color derived from it.
enum Artwork {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func load(_ url: URL) async -> UIImage? {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return UIImage(data: data)
    }

    /// The cover's average color, pushed toward something that glows on a dark stage.
    static func tint(of image: UIImage) -> Color? {
        guard let input = CIImage(image: image) else { return nil }
        let filter = CIFilter.areaAverage()
        filter.inputImage = input
        filter.extent = input.extent
        guard let output = filter.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(output, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let color = UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                            blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return nil }
        // A grey cover has no meaningful hue; let the caller keep its fallback.
        guard s > 0.08 else { return nil }
        return Color(hue: h, saturation: max(s, 0.55), brightness: min(max(b, 0.7), 0.95))
    }

    /// A stable color per song for when there is no cover (or it is grey).
    static func fallbackTint(for trackID: String) -> Color {
        let hash = trackID.unicodeScalars.reduce(UInt32(7)) { ($0 &* 31) &+ $1.value }
        // Stay on the cool-to-magenta half of the wheel so the coral accent keeps its contrast.
        let hue = 0.55 + Double(hash % 1000) / 1000 * 0.35
        return Color(hue: hue, saturation: 0.65, brightness: 0.9)
    }
}
