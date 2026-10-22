import SwiftUI

struct ShredderView: View {
    @Environment(AppState.self) private var state
    @State private var confirm = false
    @State private var targeted = false

    var body: some View {
        let model = state.shredder
        VStack(spacing: 0) {
            ModuleHeader(module: .shredder, subtitle: "Apague ficheiros sensíveis sem deixar rasto")
            if let msg = model.message {
                StatusBanner(text: msg, icon: "info.circle", actionTitle: "OK") { model.message = nil }
                    .padding(.horizontal, 32).padding(.bottom, 8)
            }
            GlassPanel {
                if model.items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "scissors").font(.system(size: 64)).symbolRenderingMode(.hierarchical)
                        Text("Arraste ficheiros ou pastas para aqui").font(.title2.bold())
                        Text("O conteúdo é sobrescrito antes de ser apagado.").foregroundStyle(.secondary)
                        Button("Escolher ficheiros…") { pick(model) }.buttonStyle(.bordered).controlSize(.large)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(model.items, id: \.self) { url in
                            HStack {
                                FileIcon(url: url, size: 28)
                                VStack(alignment: .leading) {
                                    Text(url.lastPathComponent)
                                    Text(url.deletingLastPathComponent().displayPath).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                SizeLabel(bytes: FS.size(of: url))
                                Button { model.items.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle") }.buttonStyle(.borderless)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8])).opacity(targeted ? 0.8 : 0.25))
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        if let url { Task { @MainActor in model.add([url]) } }
                    }
                }
                return true
            }
            .padding(.horizontal, 32).padding(.bottom, 10)
            StatusBanner(text: "Em SSDs, o macOS pode guardar cópias antigas dos dados. Para proteção total, ative o FileVault.",
                         icon: "exclamationmark.shield")
                .padding(.horizontal, 32).padding(.bottom, 10)
            ActionFooter(summary: "\(Fmt.count(model.items.count, "item", "itens")) · \(Fmt.count(AppSettings.shared.shredPasses, "passagem", "passagens"))",
                         buttonTitle: model.working ? "A destruir…" : "Destruir",
                         disabled: model.items.isEmpty || model.working,
                         secondary: ("Adicionar…", { pick(model) })) { confirm = true }
                .confirm("Destruir \(Fmt.count(model.items.count, "item", "itens"))?", isPresented: $confirm,
                         message: "Não é possível recuperá-los.", button: "Destruir") {
                    Task { await model.shredAll() }
                }
        }
    }

    private func pick(_ model: ShredderModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Adicionar"
        if panel.runModal() == .OK { model.add(panel.urls) }
    }
}
