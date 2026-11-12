// Renders the app icon (1024 x 1024, opaque) in the Midnight stage colors:
// a warm speech bubble holding a music note, over two "lyric lines".
// Usage: swiftc -O Tools/render-icon.swift -o Tools/bin/render-icon && Tools/bin/render-icon <out.png>
import AppKit

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

let space = CGColorSpaceCreateDeviceRGB()
// No alpha channel: the App Store rejects icons with transparency.
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)


func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

let coral = color(1.0, 0.48, 0.35), amber = color(1.0, 0.72, 0.30)

// Stage: indigo at the top, near black at the bottom (CoreGraphics y points up).
let stage = CGGradient(colorsSpace: space, colors: [color(0.027, 0.024, 0.06), color(0.13, 0.09, 0.33)] as CFArray,
                       locations: [0, 1])!
ctx.drawLinearGradient(stage, start: .zero, end: CGPoint(x: 0, y: size), options: [])

// Violet glow top left, warm glow bottom right.
func glow(_ c: CGColor, at p: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: space, colors: [c, c.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
}
glow(color(0.45, 0.36, 1.0, 0.75), at: CGPoint(x: 230, y: 840), radius: 620)
glow(color(1.0, 0.48, 0.35, 0.30), at: CGPoint(x: 900, y: 120), radius: 520)

// Speech bubble with a tail, filled with the spotlight gradient.
let bubble = CGMutablePath()
let box = CGRect(x: 212, y: 430, width: 600, height: 420)
bubble.addRoundedRect(in: box, cornerWidth: 130, cornerHeight: 130)
bubble.move(to: CGPoint(x: 330, y: 450))
bubble.addLine(to: CGPoint(x: 290, y: 330))
bubble.addLine(to: CGPoint(x: 450, y: 440))
bubble.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 60, color: color(1.0, 0.48, 0.35, 0.55))
ctx.addPath(bubble)
ctx.setFillColor(coral)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bubble)
ctx.clip()
let warm = CGGradient(colorsSpace: space, colors: [coral, amber] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(warm, start: CGPoint(x: 212, y: 430), end: CGPoint(x: 812, y: 850), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.restoreGState()

// The note inside the bubble.
let config = NSImage.SymbolConfiguration(pointSize: 250, weight: .heavy)
if let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor(red: 0.07, green: 0.05, blue: 0.17, alpha: 1).set()
        rect.fill(using: .sourceAtop)
        return true
    }
    let s = tinted.size
    tinted.draw(in: CGRect(x: box.midX - s.width / 2 - 8, y: box.midY - s.height / 2, width: s.width, height: s.height))
}

// Two lyric lines under the bubble: the original in white, the translation in lavender.
func bar(_ rect: CGRect, _ c: CGColor) {
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil))
    ctx.setFillColor(c)
    ctx.fillPath()
}
bar(CGRect(x: 212, y: 232, width: 600, height: 54), color(1, 1, 1, 0.96))
bar(CGRect(x: 212, y: 142, width: 410, height: 44), color(0.76, 0.70, 1.0, 0.85))

let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(out)") }
print("wrote \(out)")
