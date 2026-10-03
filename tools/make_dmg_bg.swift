// Draws the DMG window background (660x400). Run: swift tools/make_dmg_bg.swift <output.png>
import AppKit
let w = 660, h = 400
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w * 2, pixelsHigh: h * 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: w, height: h)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGradient(colors: [NSColor(red: 0.06, green: 0.12, blue: 0.24, alpha: 1), NSColor(red: 0.10, green: 0.42, blue: 0.50, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)
func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ alpha: CGFloat, y: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    (s as NSString).draw(in: NSRect(x: 0, y: y, width: CGFloat(w), height: size + 8),
        withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: NSColor.white.withAlphaComponent(alpha), .paragraphStyle: p])
}
text("Drag Unraid Watcher to Applications", 22, .semibold, 0.95, y: 330)
text("© 2026 Ray Munro", 12, .regular, 0.6, y: 18)
// arrow between the two icons
let a = NSBezierPath(); a.lineWidth = 6; a.lineCapStyle = .round; a.lineJoinStyle = .round
a.move(to: NSPoint(x: 285, y: 200)); a.line(to: NSPoint(x: 375, y: 200))
a.move(to: NSPoint(x: 350, y: 225)); a.line(to: NSPoint(x: 377, y: 200)); a.line(to: NSPoint(x: 350, y: 175))
NSColor.white.withAlphaComponent(0.85).setStroke(); a.stroke()
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
