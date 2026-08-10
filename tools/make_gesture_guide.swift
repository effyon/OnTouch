// Renders docs/gestures.png — a 2×2 visual guide to the default gestures.
// Run: swift tools/make_gesture_guide.swift
import AppKit

let W: CGFloat = 880, H: CGFloat = 640
let outPath = NSString(string: "~/OnTouch/docs/gestures.png").expandingTildeInPath
try? FileManager.default.createDirectory(atPath: (outPath as NSString).deletingLastPathComponent,
                                         withIntermediateDirectories: true)

func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let cream   = col(0.95, 0.93, 0.89)
let ink     = col(0.14, 0.13, 0.12)
let softInk = col(0.14, 0.13, 0.12, 0.42)
let greige  = col(0.83, 0.80, 0.74)

func serif(_ s: CGFloat) -> NSFont { NSFont(name: "Didot", size: s) ?? NSFont.systemFont(ofSize: s, weight: .light) }
func sans(_ s: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { NSFont.systemFont(ofSize: s, weight: w) }

func draw(_ s: String, _ f: NSFont, _ c: NSColor, centerX: CGFloat, y: CGFloat) {
    let a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c])
    a.draw(at: NSPoint(x: centerX - a.size().width/2, y: y))
}
func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: NSColor) {
    c.setFill(); NSBezierPath(ovalIn: NSRect(x: x-r, y: y-r, width: 2*r, height: 2*r)).fill()
}
func stroke(_ p: NSBezierPath, _ w: CGFloat, _ c: NSColor) {
    p.lineWidth = w; p.lineCapStyle = .round; p.lineJoinStyle = .round; c.setStroke(); p.stroke()
}

/// Draws one panel: a trackpad with the anchor finger plus an action glyph.
/// kind: "tapL" | "tapR" | "swipeDown2" | "tap2"
func panel(originX ox: CGFloat, originY oy: CGFloat, w pw: CGFloat, h ph: CGFloat,
           kind: String, title: String, subtitle: String) {
    let padW: CGFloat = 210, padH: CGFloat = 145
    let px = ox + (pw - padW)/2, py = oy + 84
    let pad = NSBezierPath(roundedRect: NSRect(x: px, y: py, width: padW, height: padH),
                           xRadius: 13, yRadius: 13)
    stroke(pad, 2, ink)

    let cx = px + padW/2, cy = py + padH/2

    /// Tiny letterspaced label under a finger so anchor vs. action is unambiguous.
    func tag(_ s: String, _ x: CGFloat, _ y: CGFloat) {
        let a = NSAttributedString(string: s, attributes: [
            .font: sans(8.5, .semibold), .foregroundColor: softInk, .kern: 1.1])
        a.draw(at: NSPoint(x: x - a.size().width/2, y: y))
    }

    // anchor finger: solid dot inside a dashed "parked" ring
    func anchor(at x: CGFloat, _ y: CGFloat) {
        dot(x, y, 9, ink)
        let ring = NSBezierPath(ovalIn: NSRect(x: x-17, y: y-17, width: 34, height: 34))
        ring.setLineDash([3, 3.5], count: 2, phase: 0)
        stroke(ring, 1.5, softInk)
        tag("HOLD", x, y - 34)
    }
    // action finger: solid dot with outward ripples
    func ripple(_ x: CGFloat, _ y: CGFloat, label: Bool = true) {
        dot(x, y, 9, ink)
        for (rr, a) in [(19.0, 0.5), (29.0, 0.22)] {
            let p = NSBezierPath(ovalIn: NSRect(x: x-CGFloat(rr), y: y-CGFloat(rr),
                                                width: CGFloat(rr)*2, height: CGFloat(rr)*2))
            stroke(p, 2, col(0.14, 0.13, 0.12, CGFloat(a)))
        }
        if label { tag("TAP", x, y - 44) }
    }
    func arrowDown(_ x: CGFloat, fromY: CGFloat, toY: CGFloat) {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x, y: fromY))
        p.line(to: NSPoint(x: x, y: toY))
        p.move(to: NSPoint(x: x - 7, y: toY + 9))
        p.line(to: NSPoint(x: x, y: toY))
        p.line(to: NSPoint(x: x + 7, y: toY + 9))
        stroke(p, 2, ink)
    }

    switch kind {
    case "tapL":
        anchor(at: cx + 30, cy)
        ripple(cx - 42, cy)
    case "tapR":
        anchor(at: cx - 30, cy)
        ripple(cx + 42, cy)
    case "swipeDown2":
        anchor(at: cx - 52, cy + 8)
        dot(cx + 16, cy + 34, 8, ink); arrowDown(cx + 16, fromY: cy + 26, toY: cy - 34)
        dot(cx + 48, cy + 34, 8, ink); arrowDown(cx + 48, fromY: cy + 26, toY: cy - 34)
    case "tap2":
        anchor(at: cx - 54, cy + 6)
        ripple(cx + 22, cy + 30, label: false)
        ripple(cx + 54, cy - 6, label: false)
        tag("TAP ×2", cx + 40, cy - 44)
    default: break
    }

    draw(title,    serif(26),          ink,     centerX: ox + pw/2, y: oy + 38)
    draw(subtitle, sans(13, .regular), softInk, centerX: ox + pw/2, y: oy + 16)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

cream.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()

// header
draw("Hold one finger. Act with the others.", serif(30), ink, centerX: W/2, y: H - 62)
let rule = NSBezierPath(rect: NSRect(x: W/2 - 90, y: H - 78, width: 180, height: 1.5))
ink.setFill(); rule.fill()

let bottomMargin: CGFloat = 26
let pw = W/2, ph = (H - 104 - bottomMargin)/2
panel(originX: 0,  originY: bottomMargin + ph, w: pw, h: ph, kind: "tapL",
      title: "Previous tab",  subtitle: "tap to the LEFT of the anchor")
panel(originX: pw, originY: bottomMargin + ph, w: pw, h: ph, kind: "tapR",
      title: "Next tab",      subtitle: "tap to the RIGHT of the anchor")
panel(originX: 0,  originY: bottomMargin, w: pw, h: ph, kind: "swipeDown2",
      title: "Close tab",     subtitle: "swipe DOWN with two fingers")
panel(originX: pw, originY: bottomMargin, w: pw, h: ph, kind: "tap2",
      title: "Reopen tab",    subtitle: "tap with two fingers")

NSGraphicsContext.current?.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
