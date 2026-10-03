// Draws the Towerlight app icon and writes Resources/AppIcon.icns. Run: swift tools/make_icon.swift
import AppKit

func draw(_ size: Int) -> Data {
    let s = CGFloat(size) / 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let g = ctx.cgContext
    g.scaleBy(x: s, y: s)
    let cs = CGColorSpaceCreateDeviceRGB()
    func col(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
    }
    func grad(_ cols: [CGColor], _ locs: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: cs, colors: cols as CFArray, locations: locs)! }

    // Background squircle
    let bg = CGRect(x: 100, y: 100, width: 824, height: 824)
    g.saveGState()
    g.addPath(CGPath(roundedRect: bg, cornerWidth: 185, cornerHeight: 185, transform: nil)); g.clip()
    g.drawLinearGradient(grad([col(0x0A1530), col(0x123A5E), col(0x1B7F8E)], [0, 0.55, 1]),
                         start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // faint stars
    g.setFillColor(col(0xFFFFFF, 0.35))
    for (x, y, r) in [(210.0, 840.0, 4.0), (320, 770, 3), (760, 850, 4), (850, 760, 3), (650, 880, 3), (160, 700, 3), (880, 640, 3)] {
        g.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    // Light beams from the lantern
    let lamp = CGPoint(x: 512, y: 690)
    for dir: CGFloat in [-1, 1] {
        g.saveGState()
        let p = CGMutablePath()
        p.move(to: lamp)
        p.addLine(to: CGPoint(x: 512 + dir * 520, y: 690 + 150))
        p.addLine(to: CGPoint(x: 512 + dir * 520, y: 690 - 110))
        p.closeSubpath()
        g.addPath(p); g.clip()
        g.drawLinearGradient(grad([col(0xFFE9A8, 0.85), col(0xFFE9A8, 0)], [0, 1]),
                             start: lamp, end: CGPoint(x: 512 + dir * 520, y: 690), options: [])
        g.restoreGState()
    }

    // Tower body (a NAS tower)
    let body = CGRect(x: 372, y: 170, width: 280, height: 440)
    g.saveGState()
    g.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: col(0x000000, 0.5))
    g.addPath(CGPath(roundedRect: body, cornerWidth: 38, cornerHeight: 38, transform: nil))
    g.setFillColor(col(0xD7E0EA)); g.fillPath()
    g.restoreGState()
    g.saveGState()
    g.addPath(CGPath(roundedRect: body, cornerWidth: 38, cornerHeight: 38, transform: nil)); g.clip()
    g.drawLinearGradient(grad([col(0xF4F8FC), col(0xA9B8C9)], [0, 1]), start: CGPoint(x: 372, y: 610), end: CGPoint(x: 652, y: 170), options: [])
    g.restoreGState()

    // Drive bays with status LEDs
    for i in 0..<4 {
        let y = 215 + CGFloat(i) * 92
        let slot = CGRect(x: 405, y: y, width: 214, height: 66)
        g.addPath(CGPath(roundedRect: slot, cornerWidth: 14, cornerHeight: 14, transform: nil))
        g.setFillColor(col(0x16243A)); g.fillPath()
        g.setFillColor(col(0x2B3F5C))
        for k in 0..<5 { g.fill(CGRect(x: 428 + CGFloat(k) * 18, y: y + 18, width: 6, height: 30)) }
        let led = i == 2 ? col(0xFFB020) : col(0x3DDC84)
        g.setFillColor(led); g.fillEllipse(in: CGRect(x: 580, y: y + 24, width: 18, height: 18))
    }

    // Lantern on top
    let cap = CGRect(x: 432, y: 610, width: 160, height: 34)
    g.addPath(CGPath(roundedRect: cap, cornerWidth: 12, cornerHeight: 12, transform: nil)); g.setFillColor(col(0x8FA2B8)); g.fillPath()
    g.drawRadialGradient(grad([col(0xFFF6D0), col(0xFFD25E, 0.9), col(0xFFB020, 0)], [0, 0.35, 1]),
                         startCenter: lamp, startRadius: 0, endCenter: lamp, endRadius: 150, options: [])
    g.setFillColor(col(0xFFF3C4)); g.fillEllipse(in: CGRect(x: lamp.x - 40, y: lamp.y - 40, width: 80, height: 80))
    g.restoreGState()

    NSGraphicsContext.current = nil
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let set = "Resources/AppIcon.iconset"
try? fm.removeItem(atPath: set)
try! fm.createDirectory(atPath: set, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).write(to: URL(fileURLWithPath: "\(set)/icon_\(name).png"))
}
try! draw(1024).write(to: URL(fileURLWithPath: "Resources/icon_preview.png"))
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set, "-o", "Resources/AppIcon.icns"]; try! p.run(); p.waitUntilExit()
try? fm.removeItem(atPath: set)
print("icon written, status \(p.terminationStatus)")
