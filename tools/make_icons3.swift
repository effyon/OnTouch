// Minimalist, feature-reflecting icon candidates (trackpad / gesture motifs).
// Run: swift tools/make_icons3.swift  → /tmp/icons3/
import AppKit

let S: CGFloat = 1024
let cx = S/2, cy = S/2
let outDir = "/tmp/icons3"
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

func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
let cream = col(0.95, 0.93, 0.89)
let ivory = col(0.93, 0.91, 0.86)
let ink   = col(0.14, 0.13, 0.12)

func background(_ base: NSColor, _ top: NSColor) {
    let m = S * 0.07
    let rect = NSRect(x: m, y: m, width: S - 2*m, height: S - 2*m)
    let r = (S - 2*m) * 0.2237
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).addClip()
    NSGradient(starting: top, ending: base)!.draw(in: rect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
}

func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: NSColor) {
    c.setFill(); NSBezierPath(ovalIn: NSRect(x: x-r, y: y-r, width: 2*r, height: 2*r)).fill()
}

func stroke(_ p: NSBezierPath, _ w: CGFloat, _ c: NSColor) {
    p.lineWidth = w; p.lineCapStyle = .round; p.lineJoinStyle = .round; c.setStroke(); p.stroke()
}

func serifText(_ s: String, size: CGFloat, color: NSColor, cyOffset: CGFloat) {
    let font = NSFont(name: "Didot", size: size) ?? NSFont.systemFont(ofSize: size, weight: .light)
    let st = NSMutableParagraphStyle(); st.alignment = .center
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: st])
    let bb = a.size()
    a.draw(in: NSRect(x: cx - bb.width/2, y: cy + cyOffset - bb.height/2, width: bb.width, height: bb.height))
}

// --- A: trackpad outline + two finger dots + swipe arrow ---
render("A-pad-swipe") {
    background(cream, ivory)
    let w = S*0.52, h = S*0.40
    let pad = NSBezierPath(roundedRect: NSRect(x: cx-w/2, y: cy-h/2, width: w, height: h), xRadius: S*0.05, yRadius: S*0.05)
    stroke(pad, S*0.016, ink)
    dot(cx - S*0.10, cy + S*0.05, S*0.028, ink)
    dot(cx - S*0.10, cy - S*0.05, S*0.028, ink)
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: cx - S*0.03, y: cy))
    arrow.line(to: NSPoint(x: cx + S*0.16, y: cy))
    arrow.move(to: NSPoint(x: cx + S*0.09, y: cy + S*0.05))
    arrow.line(to: NSPoint(x: cx + S*0.16, y: cy))
    arrow.line(to: NSPoint(x: cx + S*0.09, y: cy - S*0.05))
    stroke(arrow, S*0.016, ink)
}

// --- B: two fingertips with motion trails (abstract two-finger swipe) ---
render("B-two-finger") {
    background(cream, ivory)
    let r = S*0.05, gap = S*0.085
    dot(cx + S*0.10, cy + gap, r, ink)
    dot(cx + S*0.10, cy - gap, r, ink)
    for sign in [CGFloat(1), -1] {
        let t = NSBezierPath()
        t.move(to: NSPoint(x: cx - S*0.18, y: cy + sign*gap))
        t.curve(to: NSPoint(x: cx + S*0.02, y: cy + sign*gap),
                controlPoint1: NSPoint(x: cx - S*0.10, y: cy + sign*gap),
                controlPoint2: NSPoint(x: cx - S*0.06, y: cy + sign*gap))
        stroke(t, S*0.018, ink)
    }
}

// --- C: single fingertip tracing a sweeping arc (one-finger gesture) ---
render("C-arc") {
    background(cream, ivory)
    let arc = NSBezierPath()
    arc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: S*0.20,
                  startAngle: 200, endAngle: 340, clockwise: false)
    stroke(arc, S*0.018, ink)
    // fingertip dot at the leading end (~340°)
    let a = CGFloat(340) * .pi/180
    dot(cx + cos(a)*S*0.20, cy + sin(a)*S*0.20, S*0.05, ink)
}

// --- D: trackpad + two dots, with a quiet 'on' serif beneath ---
render("D-pad-on") {
    background(cream, ivory)
    let w = S*0.46, h = S*0.34, oy = S*0.06
    let pad = NSBezierPath(roundedRect: NSRect(x: cx-w/2, y: cy+oy-h/2, width: w, height: h), xRadius: S*0.045, yRadius: S*0.045)
    stroke(pad, S*0.016, ink)
    dot(cx - S*0.06, cy+oy, S*0.03, ink)
    dot(cx + S*0.06, cy+oy, S*0.03, ink)
    serifText("on", size: S*0.16, color: ink, cyOffset: -S*0.28)
}

print("done")
