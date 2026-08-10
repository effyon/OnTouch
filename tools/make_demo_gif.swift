// Renders docs/demo.gif — an animated demo of the anchored tab-switch gesture.
// Run: swift tools/make_demo_gif.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

let W: CGFloat = 760, H: CGFloat = 440
let outPath = NSString(string: "~/OnTouch/docs/demo.gif").expandingTildeInPath
try? FileManager.default.createDirectory(atPath: (outPath as NSString).deletingLastPathComponent,
                                         withIntermediateDirectories: true)

func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let cream    = col(0.95, 0.93, 0.89)
let ink      = col(0.14, 0.13, 0.12)
let greige   = col(0.83, 0.80, 0.74)
let softInk  = col(0.14, 0.13, 0.12, 0.45)

struct Frame {
    var tab: Int          // active tab index 0..3
    var anchor: Bool      // anchor finger planted
    var tap: String?      // "left" | "right" | nil
    var ripple: CGFloat   // 0..1 ripple progress
    var caption: String
}

// Timeline: idle → plant anchor → tap right ×2 → tap left → lift.
var frames: [Frame] = []
func hold(_ n: Int, _ f: Frame) { for _ in 0..<n { frames.append(f) } }

let capIdle   = "rest one finger to anchor"
let capNext   = "tap right  →  next tab"
let capPrev   = "tap left  →  previous tab"

hold(6,  Frame(tab: 0, anchor: false, tap: nil, ripple: 0, caption: capIdle))
hold(6,  Frame(tab: 0, anchor: true,  tap: nil, ripple: 0, caption: capIdle))
for i in 0..<3 { frames.append(Frame(tab: 0, anchor: true, tap: "right", ripple: CGFloat(i)/2, caption: capNext)) }
hold(5,  Frame(tab: 1, anchor: true,  tap: nil, ripple: 0, caption: capNext))
for i in 0..<3 { frames.append(Frame(tab: 1, anchor: true, tap: "right", ripple: CGFloat(i)/2, caption: capNext)) }
hold(6,  Frame(tab: 2, anchor: true,  tap: nil, ripple: 0, caption: capNext))
for i in 0..<3 { frames.append(Frame(tab: 2, anchor: true, tap: "left", ripple: CGFloat(i)/2, caption: capPrev)) }
hold(8,  Frame(tab: 1, anchor: true,  tap: nil, ripple: 0, caption: capPrev))
hold(5,  Frame(tab: 1, anchor: false, tap: nil, ripple: 0, caption: capIdle))

func serif(_ size: CGFloat) -> NSFont {
    NSFont(name: "Didot", size: size) ?? NSFont.systemFont(ofSize: size, weight: .light)
}
func sans(_ size: CGFloat, _ w: NSFont.Weight = .medium) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: w)
}

func draw(_ s: String, _ font: NSFont, _ color: NSColor, centerX: CGFloat, y: CGFloat) {
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
    let sz = a.size()
    a.draw(at: NSPoint(x: centerX - sz.width/2, y: y))
}

func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ c: NSColor) {
    c.setFill()
    NSBezierPath(ovalIn: NSRect(x: x-r, y: y-r, width: 2*r, height: 2*r)).fill()
}

func render(_ f: Frame) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    cream.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()

    // ---- browser window mock ----
    let bx: CGFloat = 40, by: CGFloat = 250, bw: CGFloat = 680, bh: CGFloat = 170
    let win = NSBezierPath(roundedRect: NSRect(x: bx, y: by, width: bw, height: bh),
                           xRadius: 10, yRadius: 10)
    win.lineWidth = 2; ink.setStroke(); win.stroke()

    // tabs
    let tabW: CGFloat = 160, tabH: CGFloat = 38, gap: CGFloat = 8
    let tabY = by + bh - tabH - 10
    for i in 0..<4 {
        let x = bx + 12 + CGFloat(i) * (tabW + gap)
        let r = NSRect(x: x, y: tabY, width: tabW, height: tabH)
        let p = NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7)
        if i == f.tab { ink.setFill(); p.fill() }
        else { greige.setFill(); p.fill() }
        let label = "Tab \(i+1)"
        draw(label, sans(13, i == f.tab ? .semibold : .regular),
             i == f.tab ? cream : softInk, centerX: r.midX, y: r.midY - 8)
    }

    // page content placeholder lines
    greige.setFill()
    for (i, wRatio) in [0.72, 0.55, 0.63, 0.40].enumerated() {
        let lw = (bw - 48) * CGFloat(wRatio)
        NSRect(x: bx + 24, y: tabY - 28 - CGFloat(i) * 20, width: lw, height: 8).fill()
    }

    // ---- trackpad ----
    let px: CGFloat = 290, py: CGFloat = 72, pw: CGFloat = 180, ph: CGFloat = 132
    let pad = NSBezierPath(roundedRect: NSRect(x: px, y: py, width: pw, height: ph),
                           xRadius: 12, yRadius: 12)
    pad.lineWidth = 2; ink.setStroke(); pad.stroke()

    let cxPad = px + pw/2, cyPad = py + ph/2

    if f.anchor {
        // anchor finger: solid dot with a held ring
        dot(cxPad - 26, cyPad, 9, ink)
        let ring = NSBezierPath(ovalIn: NSRect(x: cxPad - 26 - 17, y: cyPad - 17, width: 34, height: 34))
        ring.lineWidth = 1.5; softInk.setStroke(); ring.stroke()
    }

    if let side = f.tap {
        let tx = side == "right" ? cxPad + 38 : cxPad - 74
        dot(tx, cyPad, 9, ink)
        // ripple
        let rr = 12 + f.ripple * 16
        let alpha = 0.45 * (1 - f.ripple)
        let rip = NSBezierPath(ovalIn: NSRect(x: tx - rr, y: cyPad - rr, width: 2*rr, height: 2*rr))
        rip.lineWidth = 2
        col(0.14, 0.13, 0.12, alpha).setStroke(); rip.stroke()
    }

    draw(f.caption, serif(21), ink, centerX: W/2, y: 28)

    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.cgImage!
}

let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                 frames.count, nil) else {
    fatalError("could not create gif destination")
}
CGImageDestinationSetProperties(dest, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
] as CFDictionary)
for f in frames {
    CGImageDestinationAddImage(dest, render(f), [
        kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.09]
    ] as CFDictionary)
}
CGImageDestinationFinalize(dest)
print("wrote \(outPath) (\(frames.count) frames)")
