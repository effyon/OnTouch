// Renders refined, minimalist "Khaite-vibe" app-icon candidates to /tmp/icons2/.
// Run: swift tools/make_icons2.swift
import AppKit

let S: CGFloat = 1024
let outDir = "/tmp/icons2"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ name: String, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("wrote \(name).png")
}

func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// Solid (optionally very faint tonal) squircle background.
func background(_ base: NSColor, top: NSColor? = nil) {
    let m = S * 0.07
    let rect = NSRect(x: m, y: m, width: S - 2*m, height: S - 2*m)
    let r = (S - 2*m) * 0.2237
    let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    if let top = top {
        NSGradient(starting: top, ending: base)!.draw(in: rect, angle: -90)
    } else {
        base.setFill(); rect.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
}

// An elegant high-contrast serif, with graceful fallbacks.
func serif(_ size: CGFloat) -> NSFont {
    for n in ["Didot", "Bodoni 72", "Hoefler Text", "Baskerville"] {
        if let f = NSFont(name: n, size: size) { return f }
    }
    return NSFont.systemFont(ofSize: size, weight: .light)
}

func wordmark(_ str: String, font: NSFont, color: NSColor, kern: CGFloat, dy: CGFloat = 0) {
    let style = NSMutableParagraphStyle(); style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color,
                                                 .paragraphStyle: style, .kern: kern]
    let a = NSAttributedString(string: str, attributes: attrs)
    let bb = a.size()
    a.draw(in: NSRect(x: 0, y: (S - bb.height)/2 + dy, width: S, height: bb.height))
}

let ivory    = col(0.93, 0.91, 0.86)
let cream    = col(0.95, 0.93, 0.89)
let charcoal = col(0.14, 0.13, 0.12)
let greige   = col(0.80, 0.76, 0.70)
let taupeInk = col(0.46, 0.42, 0.37)

// 1 — Ivory: warm off-white, charcoal Didot "On"
render("1-ivory") {
    background(cream, top: ivory)
    wordmark("On", font: serif(S * 0.34), color: charcoal, kern: S * 0.004)
}

// 2 — Noir: warm charcoal, ivory Didot "On"
render("2-noir") {
    background(charcoal, top: col(0.18, 0.17, 0.16))
    wordmark("On", font: serif(S * 0.34), color: cream, kern: S * 0.004)
}

// 3 — Tonal: greige, tone-on-tone lowercase "on" (most subtle)
render("3-tonal") {
    background(greige)
    wordmark("on", font: serif(S * 0.40), color: taupeInk, kern: S * 0.002)
}

// 4 — Hairline: ivory with a thin rule beneath the wordmark (fashion-label feel)
render("4-hairline") {
    background(cream, top: ivory)
    wordmark("On", font: serif(S * 0.30), color: charcoal, kern: S * 0.006, dy: S * 0.04)
    let lw = S * 0.30, lx = (S - lw)/2, ly = S * 0.40
    let rule = NSBezierPath(rect: NSRect(x: lx, y: ly, width: lw, height: S * 0.006))
    charcoal.setFill(); rule.fill()
}

print("done")
