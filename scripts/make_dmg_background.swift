import AppKit

// Installer window background (640×400 pt). Usage: swift make_dmg_background.swift <output.png> <scale>
let args = CommandLine.arguments
let out = URL(fileURLWithPath: args[1])
let scale = Double(args.count > 2 ? args[2] : "1") ?? 1
let w = 640.0, h = 400.0

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * scale), pixelsHigh: Int(h * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: w, height: h)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// The app's identity: ivory and ink, like the icon.
let bounds = NSRect(x: 0, y: 0, width: w, height: h)
let ink = NSColor(red: 0x1F / 255.0, green: 0x1F / 255.0, blue: 0x1C / 255.0, alpha: 1)
NSColor(red: 0xF5 / 255.0, green: 0xF4 / 255.0, blue: 0xEE / 255.0, alpha: 1).setFill()
bounds.fill()

func text(_ s: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, y: CGFloat) {
    let p = NSMutableParagraphStyle()
    p.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight, width: size > 20 ? .expanded : .standard),
        .foregroundColor: ink.withAlphaComponent(alpha),
        .paragraphStyle: p,
    ]
    NSAttributedString(string: s, attributes: attrs).draw(in: NSRect(x: 20, y: y, width: w - 40, height: size * 1.6))
}

// Coordinates with the origin at the bottom (AppKit). The icons are centered at y = 200 (from the top) → 200 (from the bottom).
text("Install Prune", size: 24, weight: .semibold, alpha: 1, y: h - 70)
text("Drag the icon to the Applications folder", size: 14, weight: .regular, alpha: 0.7, y: h - 98)

// Arrow between the app (x = 170) and Applications (x = 470).
let arrow = NSBezierPath()
let y = h - 210
arrow.move(to: NSPoint(x: 262, y: y))
arrow.line(to: NSPoint(x: 370, y: y))
arrow.lineWidth = 3
arrow.lineCapStyle = .round
ink.setStroke()
arrow.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 384, y: y))
head.line(to: NSPoint(x: 364, y: y + 13))
head.line(to: NSPoint(x: 364, y: y - 13))
head.close()
ink.setFill()
head.fill()

text("First launch blocked by macOS? Open “How to open.txt”.", size: 12, weight: .medium, alpha: 0.6, y: 28)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
