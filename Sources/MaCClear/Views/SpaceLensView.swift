import SwiftUI

struct SpaceLensView: View {
    @Environment(AppState.self) private var state
    @State private var confirming = false

    var body: some View {
        let model = state.spaceLens
        VStack(spacing: 0) {
            if model.scanning {
                ScanningView(module: .spaceLens, title: "A construir o mapa de \(model.target.lastPathComponent)…",
                             detail: model.progressText) { model.cancel() }
            } else if let current = model.current {
                ModuleHeader(module: .spaceLens, subtitle: "\(current.name) · \(Fmt.bytes(current.size))") {
                    Button { Task { await model.scan(model.target) } } label: { Label("Analisar de novo", systemImage: "arrow.clockwise") }
                        .buttonStyle(.bordered)
                    Button("Outra pasta…") { pickFolder(model) }.buttonStyle(.bordered)
                }
                breadcrumb(model, current)
                if let msg = model.message {
                    StatusBanner(text: msg, icon: "checkmark.circle", actionTitle: "OK") { model.message = nil }
                        .padding(.horizontal, 32).padding(.bottom, 8)
                }
                HStack(spacing: 14) {
                    GlassPanel { list(model, current) }.frame(width: 340)
                    GlassPanel {
                        TreemapView(node: current, marked: model.marked, hovered: Binding(get: { model.hovered }, set: { model.hovered = $0 })) { node in
                            if node.isDirectory, !node.children.isEmpty { model.current = node }
                        }
                        .padding(6)
                        .overlay(alignment: .bottomLeading) {
                            if let h = model.hovered {
                                Text("\(h.name) — \(Fmt.bytes(h.size))").font(.callout.bold())
                                    .padding(8).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8)).padding(12)
                            }
                        }
                    }
                }
                .padding(.horizontal, 32).padding(.bottom, 14)
                ActionFooter(summary: "Selecionado: \(Fmt.bytes(model.markedSize))", buttonTitle: "Remover",
                             disabled: model.marked.isEmpty) { confirming = true }
                    .confirm("Remover \(model.marked.count) item(ns)?", isPresented: $confirming,
                             message: AppSettings.shared.filesDeleteMode == .trash ? "Serão movidos para o Lixo." : "Serão apagados definitivamente.",
                             button: "Remover") { Task { await model.removeMarked() } }
            } else {
                ModuleHeader(module: .spaceLens)
                VStack(spacing: 24) {
                    ModuleArtwork(module: .spaceLens).frame(width: 220, height: 220)
                    Text("Veja o que ocupa espaço").font(Theme.display(30))
                    Text("Um mapa visual de pastas e ficheiros, do maior para o mais pequeno. Clique para explorar.")
                        .font(.title3).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button { Task { await model.scan(home) } } label: { Label("Pasta pessoal", systemImage: "house") }
                        ForEach(model.volumes, id: \.self) { v in
                            Button { Task { await model.scan(v) } } label: {
                                Label(v.path == "/" ? "Disco de arranque" : v.lastPathComponent, systemImage: "internaldrive")
                            }
                        }
                        Button("Escolher pasta…") { pickFolder(model) }
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                    if !Permissions.hasFullDiskAccess {
                        Text("Sem Acesso Total ao Disco, algumas pastas protegidas não serão contabilizadas.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func pickFolder(_ model: SpaceLensModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Analisar"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await model.scan(url) }
        }
    }

    private func breadcrumb(_ model: SpaceLensModel, _ current: DiskNode) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(current.path) { n in
                    Button(n.name.isEmpty ? "/" : n.name) { model.current = n }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(n == current ? Theme.selection : Theme.inset, in: Capsule())
                    if n != current { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
        .padding(.horizontal, 32).padding(.bottom, 10)
    }

    private func list(_ model: SpaceLensModel, _ current: DiskNode) -> some View {
        List(current.children) { n in
            HStack(spacing: 8) {
                CheckBox(state: model.marked.contains(n)) {
                    if model.marked.contains(n) { model.marked.remove(n) } else { model.marked.insert(n) }
                }
                .disabled(n.isAggregate || !SafetyGuard.canDelete(n.url))
                .opacity(n.isAggregate ? 0 : 1)
                if n.isAggregate { Image(systemName: "ellipsis.circle").frame(width: 22) } else { FileIcon(url: n.url, size: 22) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(n.name).lineLimit(1).truncationMode(.middle)
                    GeometryReader { g in
                        Capsule().fill(Theme.accent)
                            .frame(width: max(2, g.size.width * CGFloat(current.size > 0 ? Double(n.size) / Double(current.size) : 0)))
                    }
                    .frame(height: 3)
                }
                Spacer()
                SizeLabel(bytes: n.size).font(.caption)
                if n.isDirectory && !n.children.isEmpty {
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if n.isDirectory, !n.children.isEmpty { model.current = n } }
            .onHover { if $0 { model.hovered = n } }
            .contextMenu { if !n.isAggregate { Button("Mostrar no Finder") { FS.reveal(n.url) } } }
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
    }
}

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
