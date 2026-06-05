// Final icon: two fingertips with motion trails (two-finger swipe), centered.
// Run: swift tools/make_final.swift  → /tmp/icons_final/{ivory,noir}.png
import AppKit

let S: CGFloat = 1024
let cx = S/2, cy = S/2
let outDir = "/tmp/icons_final"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func col(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
let cream = col(0.95, 0.93, 0.89), ivory = col(0.93, 0.91, 0.86)
let charcoal = col(0.14, 0.13, 0.12), charcoalTop = col(0.18, 0.17, 0.16)

func render(_ name: String, base: NSColor, top: NSColor, ink: NSColor) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let m = S * 0.07
    let rect = NSRect(x: m, y: m, width: S - 2*m, height: S - 2*m)
    let r = (S - 2*m) * 0.2237
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).addClip()
    NSGradient(starting: top, ending: base)!.draw(in: rect, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let gap = S*0.080, dotR = S*0.046, dotX = cx + S*0.105
    for sign in [CGFloat(1), -1] {
        let y = cy + sign*gap
        let p = NSBezierPath()
        p.move(to: NSPoint(x: cx - S*0.205, y: y))
        p.line(to: NSPoint(x: dotX - dotR - S*0.022, y: y))
        p.lineWidth = S*0.020; p.lineCapStyle = .round; ink.setStroke(); p.stroke()
        ink.setFill()
        NSBezierPath(ovalIn: NSRect(x: dotX-dotR, y: y-dotR, width: 2*dotR, height: 2*dotR)).fill()
    }

    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
    print("wrote \(name).png")
}

render("ivory", base: cream, top: ivory, ink: charcoal)
render("noir", base: charcoal, top: charcoalTop, ink: cream)
print("done")
