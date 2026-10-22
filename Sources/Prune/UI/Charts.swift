import SwiftUI

/// Anel de percentagem (usado no Painel e na barra de menus).
struct RingGauge: View {
    let value: Double
    var lineWidth: CGFloat = 10
    var color: Color = Theme.accent
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: value)
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let step = values.count > 1 ? w / CGFloat(values.count - 1) : w
            Path { p in
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: CGFloat(i) * step, y: h - CGFloat(min(1, v)) * h)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            .stroke(Theme.accent, lineWidth: 1.5)
            Path { p in
                p.move(to: CGPoint(x: 0, y: h))
                for (i, v) in values.enumerated() {
                    p.addLine(to: CGPoint(x: CGFloat(i) * step, y: h - CGFloat(min(1, v)) * h))
                }
                p.addLine(to: CGPoint(x: w, y: h))
            }
            .fill(LinearGradient(colors: [Theme.accent.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
        }
    }
}
