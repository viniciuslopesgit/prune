import SwiftUI

/// Treemap "squarified": área proporcional ao tamanho.
struct TreemapView: View {
    let node: DiskNode
    let marked: Set<DiskNode>
    @Binding var hovered: DiskNode?
    let onOpen: (DiskNode) -> Void

    private static let palette: [Color] = [
        // Tons de jardim: salva, oliva, trigo, casca, ardósia, pedra.
        Color(hex: 0x5E7A4F), Color(hex: 0xC9A66B), Color(hex: 0x4F6B70), Color(hex: 0x8FAE7C),
        Color(hex: 0x9C7A54), Color(hex: 0x7D8A5A), Color(hex: 0xA89F86), Color(hex: 0x6E6A60),
    ]

    var body: some View {
        GeometryReader { geo in
            let items = Array(node.children.filter { $0.size > 0 }.prefix(80))
            let rects = Treemap.layout(sizes: items.map { Double($0.size) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, n in
                    let r = rects[i].insetBy(dx: 1.5, dy: 1.5)
                    if r.width > 1 && r.height > 1 {
                        tile(n, color: Self.palette[i % Self.palette.count], rect: r)
                            .frame(width: r.width, height: r.height)
                            .offset(x: r.minX, y: r.minY)
                    }
                }
            }
        }
    }

    private func tile(_ n: DiskNode, color: Color, rect: CGRect) -> some View {
        let isHover = hovered == n
        return RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(colors: [color.opacity(n.isAggregate ? 0.18 : 0.62), color.opacity(n.isAggregate ? 0.12 : 0.42)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(marked.contains(n) ? Color.primary : Color.primary.opacity(isHover ? 0.6 : 0.1),
                                                                    lineWidth: marked.contains(n) ? 3 : 1))
            .overlay(alignment: .topLeading) {
                if rect.width > 70 && rect.height > 34 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(n.name).font(.caption.bold()).lineLimit(1)
                        Text(Fmt.bytes(n.size)).font(.caption2).opacity(0.8)
                    }
                    .padding(6)
                }
            }
            .contentShape(Rectangle())
            .onHover { if $0 { hovered = n } else if hovered == n { hovered = nil } }
            .onTapGesture { onOpen(n) }
            .help("\(n.name) — \(Fmt.bytes(n.size))")
    }
}

enum Treemap {
    static func layout(sizes: [Double], in rect: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: sizes.count)
        let total = sizes.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }
        let scale = Double(rect.width * rect.height) / total
        let areas = sizes.map { $0 * scale }
        var remaining = rect
        var i = 0

        func worst(_ row: [Double], _ side: Double) -> Double {
            let s = row.reduce(0, +)
            guard s > 0, side > 0 else { return .infinity }
            let s2 = s * s, w2 = side * side
            return row.map { max(w2 * $0 / s2, s2 / (w2 * $0)) }.max() ?? .infinity
        }

        while i < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var row = [areas[i]]
            var j = i + 1
            while j < areas.count {
                let candidate = row + [areas[j]]
                if worst(candidate, side) <= worst(row, side) { row = candidate; j += 1 } else { break }
            }
            let sum = row.reduce(0, +)
            let thickness = side > 0 ? sum / side : 0
            if remaining.width >= remaining.height {
                var y = Double(remaining.minY)
                for k in i..<j {
                    let h = thickness > 0 ? areas[k] / thickness : 0
                    result[k] = CGRect(x: Double(remaining.minX), y: y, width: thickness, height: h)
                    y += h
                }
                remaining = CGRect(x: remaining.minX + thickness, y: remaining.minY,
                                   width: max(0, remaining.width - thickness), height: remaining.height)
            } else {
                var x = Double(remaining.minX)
                for k in i..<j {
                    let w = thickness > 0 ? areas[k] / thickness : 0
                    result[k] = CGRect(x: x, y: Double(remaining.minY), width: w, height: thickness)
                    x += w
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + thickness,
                                   width: remaining.width, height: max(0, remaining.height - thickness))
            }
            i = j
        }
        return result
    }
}
