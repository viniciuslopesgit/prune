import AppKit

// Desenha o ícone do Prune: uma folha minimal, escura, sobre fundo marfim.
// Uso: swift make_icon.swift <saida.png> [lado em píxeis, por omissão 1024]
// Desenha em vetor ao tamanho pedido (nos tamanhos pequenos a nervura é omitida, para a folha ficar legível).
let args = CommandLine.arguments
let px = Int(args.count > 2 ? args[2] : "1024") ?? 1024
let s = CGFloat(px) / 1024  // tudo é desenhado numa grelha de 1024 e escalado

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let ivory: UInt32 = 0xF5F4EE
let ink: UInt32 = 0x1F1F1C

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: s, y: s)

// Corpo do ícone na grelha do macOS: 824×824 centrado, cantos arredondados.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: rgb(0x000000, 0.22))
ctx.addPath(bodyPath)
ctx.setFillColor(rgb(ivory))
ctx.fillPath()
ctx.restoreGState()

// Contorno muito leve, para o marfim não se perder em fundos claros.
ctx.addPath(bodyPath)
ctx.setStrokeColor(rgb(0x000000, 0.08))
ctx.setLineWidth(2)
ctx.strokePath()

// Folha: centrada, inclinada 45° (ponta para cima e para a direita).
let small = px <= 64
ctx.saveGState()
ctx.translateBy(x: 512, y: 512)
ctx.rotate(by: .pi / 4)

// No referencial da folha: base em (-L, 0), ponta em (L, 0).
let L: CGFloat = small ? 250 : 235
let W: CGFloat = small ? 150 : 132
let leaf = CGMutablePath()
leaf.move(to: CGPoint(x: -L, y: 0))
leaf.addCurve(to: CGPoint(x: L, y: 0), control1: CGPoint(x: -L * 0.55, y: W * 1.25), control2: CGPoint(x: L * 0.45, y: W * 0.95))
leaf.addCurve(to: CGPoint(x: -L, y: 0), control1: CGPoint(x: L * 0.45, y: -W * 0.95), control2: CGPoint(x: -L * 0.55, y: -W * 1.25))
leaf.closeSubpath()
ctx.addPath(leaf)
ctx.setFillColor(rgb(ink))
ctx.fillPath()

// Pé: um traço curto que sai da base.
let stem = CGMutablePath()
stem.move(to: CGPoint(x: -L + 20, y: 0))
stem.addLine(to: CGPoint(x: -L - (small ? 70 : 85), y: 0))
ctx.addPath(stem)
ctx.setStrokeColor(rgb(ink))
ctx.setLineWidth(small ? 30 : 22)
ctx.setLineCap(.round)
ctx.strokePath()

// Nervura central em negativo, que não chega à ponta.
if !small {
    let rib = CGMutablePath()
    rib.move(to: CGPoint(x: -L * 0.62, y: 0))
    rib.addQuadCurve(to: CGPoint(x: L * 0.55, y: 6), control: CGPoint(x: 0, y: 10))
    ctx.addPath(rib)
    ctx.setStrokeColor(rgb(ivory))
    ctx.setLineWidth(14)
    ctx.setLineCap(.round)
    ctx.strokePath()
}
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
