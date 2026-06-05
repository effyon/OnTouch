// Renders several candidate app-icon designs for OnTouch to /tmp/icons/.
// Run: swift tools/make_icons.swift
import AppKit

let S: CGFloat = 1024
let outDir = "/tmp/icons"
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
    let url = URL(fileURLWithPath: "\(outDir)/\(name).png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote \(url.path)")
}

func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// Rounded-square (squircle-ish) background filling the icon grid, with a vertical gradient.
func background(_ c1: NSColor, _ c2: NSColor) {
    let m = S * 0.07
    let rect = NSRect(x: m, y: m, width: S - 2*m, height: S - 2*m)
    let r = (S - 2*m) * 0.2237
    let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    NSGradient(starting: c1, ending: c2)!.draw(in: rect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
}

func text(_ str: String, fontSize: CGFloat, weight: NSFont.Weight, color: NSColor, dy: CGFloat = 0) {
    let style = NSMutableParagraphStyle(); style.alignment = .center
    let f = NSFont.systemFont(ofSize: fontSize, weight: weight)
    let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color, .paragraphStyle: style]
    let a = NSAttributedString(string: str, attributes: attrs)
    let bb = a.size()
    a.draw(in: NSRect(x: 0, y: (S - bb.height)/2 + dy, width: S, height: bb.height))
}

// ---- Variant 1: Toggle "On" (pun on the name) ----
render("1-toggle") {
    background(col(0.02, 0.80, 0.74), col(0.0, 0.46, 0.92))
    // toggle track
    let tw = S * 0.52, th = S * 0.30
    let tx = (S - tw)/2, ty = S * 0.50
    let track = NSBezierPath(roundedRect: NSRect(x: tx, y: ty, width: tw, height: th),
                             xRadius: th/2, yRadius: th/2)
    col(1, 1, 1, 0.95).setFill(); track.fill()
    // knob (on the right = "on")
    let kd = th * 0.78, kp = (th - kd)/2
    let knob = NSBezierPath(ovalIn: NSRect(x: tx + tw - kd - kp, y: ty + kp, width: kd, height: kd))
    col(0.0, 0.50, 0.92).setFill(); knob.fill()
    text("On", fontSize: S * 0.20, weight: .heavy, color: .white, dy: -S * 0.18)
}

// ---- Variant 2: Bold wordmark ----
render("2-wordmark") {
    background(col(0.40, 0.32, 0.95), col(0.92, 0.26, 0.60))
    text("On", fontSize: S * 0.50, weight: .heavy, color: .white)
}

// ---- Variant 3: Touch ripple ----
render("3-ripple") {
    background(col(0.10, 0.42, 0.97), col(0.18, 0.80, 0.96))
    // concentric ripple rings centered
    for (i, alpha) in [(3, 0.18), (2, 0.30), (1, 0.5)] as [(Int, Double)] {
        let rr = S * (0.16 + 0.085 * CGFloat(i))
        let ring = NSBezierPath(ovalIn: NSRect(x: S/2 - rr, y: S/2 - rr, width: 2*rr, height: 2*rr))
        ring.lineWidth = S * 0.022
        col(1, 1, 1, CGFloat(alpha)).setStroke(); ring.stroke()
    }
    // fingertip dot
    let dr = S * 0.085
    let dot = NSBezierPath(ovalIn: NSRect(x: S/2 - dr, y: S/2 - dr, width: 2*dr, height: 2*dr))
    col(1, 1, 1, 1).setFill(); dot.fill()
    text("On", fontSize: S * 0.17, weight: .bold, color: .white, dy: -S * 0.30)
}

// ---- Variant 4: Trackpad ----
render("4-trackpad") {
    background(col(0.18, 0.20, 0.26), col(0.09, 0.10, 0.14))
    // trackpad surface
    let pw = S * 0.56, ph = S * 0.46
    let px = (S - pw)/2, py = S * 0.30
    let pad = NSBezierPath(roundedRect: NSRect(x: px, y: py, width: pw, height: ph),
                           xRadius: S*0.05, yRadius: S*0.05)
    col(0.85, 0.87, 0.92, 1).setFill(); pad.fill()
    // two finger contact dots
    let dr = S * 0.045
    for cx in [px + pw*0.36, px + pw*0.60] {
        let dot = NSBezierPath(ovalIn: NSRect(x: cx - dr, y: py + ph*0.52 - dr, width: 2*dr, height: 2*dr))
        col(0.0, 0.55, 0.95, 1).setFill(); dot.fill()
    }
    text("On", fontSize: S * 0.16, weight: .heavy, color: col(0.10, 0.12, 0.16), dy: -S * 0.04)
}

print("done")
