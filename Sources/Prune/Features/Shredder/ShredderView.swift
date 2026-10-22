import SwiftUI

struct ShredderView: View {
    @Environment(AppState.self) private var state
    @State private var confirm = false
    @State private var targeted = false

    var body: some View {
        let model = state.shredder
        VStack(spacing: 0) {
            ModuleHeader(module: .shredder, subtitle: String(localized: "Delete sensitive files without a trace"))
            if let msg = model.message {
                StatusBanner(text: msg, icon: "info.circle", actionTitle: "OK") { model.message = nil }
                    .padding(.horizontal, 32).padding(.bottom, 8)
            }
            GlassPanel {
                if model.items.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "scissors").font(.system(size: 64)).symbolRenderingMode(.hierarchical)
                        Text("Drag files or folders here").font(.title2.bold())
                        Text("The contents are overwritten before being deleted.").foregroundStyle(.secondary)
                        Button("Choose files…") { pick(model) }.buttonStyle(.bordered).controlSize(.large)
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
            StatusBanner(text: String(localized: "On SSDs, macOS may keep old copies of the data. For full protection, turn on FileVault."),
                         icon: "exclamationmark.shield")
                .padding(.horizontal, 32).padding(.bottom, 10)
            ActionFooter(summary: "\(Fmt.items(model.items.count)) · \(Fmt.count(AppSettings.shared.shredPasses, String(localized: "pass"), String(localized: "passes")))",
                         buttonTitle: model.working ? String(localized: "Shredding…") : String(localized: "Shred"),
                         disabled: model.items.isEmpty || model.working,
                         secondary: (String(localized: "Add…"), { pick(model) })) { confirm = true }
                .confirm(String(localized: "Shred \(Fmt.items(model.items.count))?"), isPresented: $confirm,
                         message: String(localized: "They cannot be recovered."), button: String(localized: "Shred")) {
                    Task { await model.shredAll() }
                }
        }
    }

    private func pick(_ model: ShredderModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add")
        if panel.runModal() == .OK { model.add(panel.urls) }
    }
}
