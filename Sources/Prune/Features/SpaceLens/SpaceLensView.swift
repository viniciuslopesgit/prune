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
