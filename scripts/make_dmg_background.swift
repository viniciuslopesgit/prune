import AppKit

// Fundo da janela do instalador (640×400 pt). Uso: swift make_dmg_background.swift <saida.png> <escala>
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

// Identidade da app: marfim e tinta, como o ícone.
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

// Coordenadas com origem em baixo (AppKit). Os ícones ficam centrados em y = 200 (de cima) → 200 (de baixo).
text("Instalar o Prune", size: 24, weight: .semibold, alpha: 1, y: h - 70)
text("Arraste o ícone para a pasta Aplicações", size: 14, weight: .regular, alpha: 0.7, y: h - 98)

// Seta entre a app (x = 170) e Aplicações (x = 470).
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

text("Primeira abertura bloqueada pelo macOS? Abra «Como abrir.txt».", size: 12, weight: .medium, alpha: 0.6, y: 28)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
