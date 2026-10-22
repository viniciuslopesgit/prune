import SwiftUI
import UniformTypeIdentifiers

struct DuplicatesView: View {
    @Environment(AppState.self) private var state
    @State private var confirm = false

    var body: some View {
        @Bindable var model = state.duplicates
        VStack(spacing: 0) {
            if model.scanning {
                ScanningView(module: .duplicates, title: model.mode == .exact ? "A procurar duplicados…" : "A comparar fotografias…", detail: model.progressText)
            } else if !model.scanned {
                ModuleHeader(module: .duplicates)
                setup(model)
            } else {
                ModuleHeader(module: .duplicates, subtitle: model.groups.isEmpty ? "Sem duplicados" : "\(Fmt.count(model.groups.count, "grupo", "grupos")) · \(Fmt.bytes(model.wasted)) em cópias") {
                    Button("Nova análise") { model.scanned = false }.buttonStyle(.bordered)
                }
                if let msg = model.message {
                    StatusBanner(text: msg, icon: "checkmark.circle", actionTitle: "OK") { model.message = nil }
                        .padding(.horizontal, 32).padding(.bottom, 8)
                }
                if model.groups.isEmpty {
                    EmptyStateView(icon: "checkmark.circle", title: "Sem duplicados", message: "Nenhuma cópia nas pastas escolhidas.")
                } else {
                    HStack(spacing: 14) {
                        GlassPanel { groupList(model) }.frame(width: 340)
                        GlassPanel { groupDetail(model) }
                    }
                    .padding(.horizontal, 32).padding(.bottom, 14)
                    ActionFooter(summary: "\(Fmt.bytes(model.markedSize)) selecionados", buttonTitle: "Remover",
                                 disabled: model.marked.isEmpty,
                                 secondary: model.mode == .exact ? ("Seleção automática", { model.autoSelect() }) : nil) { confirm = true }
                        .confirm("Remover \(Fmt.count(model.marked.count, "cópia", "cópias"))?", isPresented: $confirm,
                                 message: "Fica sempre pelo menos uma cópia de cada ficheiro.", button: "Remover") {
                            Task { await model.removeMarked() }
                        }
                }
            }
        }
    }

    private func setup(_ model: DuplicatesModel) -> some View {
        @Bindable var model = model
        return VStack(spacing: 20) {
            ModuleArtwork(module: .duplicates).frame(width: 200, height: 200)
            Picker("", selection: $model.mode) {
                ForEach(DuplicatesModel.Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 380)
            Text(model.mode == .exact
                 ? "Ficheiros com conteúdo idêntico, mesmo com nomes diferentes."
                 : "Fotografias parecidas: sequências, edições e capturas repetidas.")
                .foregroundStyle(.secondary)
            GlassPanel {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.roots, id: \.self) { url in
                        HStack {
                            FileIcon(url: url, size: 20)
                            Text(url.displayPath)
                            Spacer()
                            Button { model.roots.removeAll { $0 == url } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }
                    Button { addFolder(model) } label: { Label("Adicionar pasta", systemImage: "plus") }.buttonStyle(.borderless)
                }
                .padding(14)
            }
            .frame(width: 460)
            if model.mode == .exact {
                Stepper("Ignorar ficheiros com menos de \(model.minKB) KB", value: $model.minKB, in: 0...10_000, step: 50).frame(width: 380)
            } else {
                HStack {
                    Text("Semelhança")
                    Slider(value: $model.similarity, in: 0.2...0.8) { Text("") } minimumValueLabel: { Text("Estrita") } maximumValueLabel: { Text("Ampla") }
                }
                .frame(width: 420)
            }
            BigActionButton(title: "Analisar", disabled: model.roots.isEmpty) { Task { await model.scan() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addFolder(_ model: DuplicatesModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { model.roots += panel.urls.filter { !model.roots.contains($0) } }
    }

    private func groupList(_ model: DuplicatesModel) -> some View {
        List(model.groups) { g in
            HStack(spacing: 10) {
                if let first = g.files.first {
                    if g.similar {
                        ThumbnailView(url: first.url, maxPixel: 96, iconSize: 32, fill: true)
                            .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        FileIcon(url: first.url, size: 32)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(first.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Text(Fmt.count(g.files.count, "cópia", "cópias")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                SizeLabel(bytes: g.similar ? g.files.reduce(0) { $0 + $1.size } : g.wasted).font(.caption)
            }
            .padding(.vertical, 3).padding(.horizontal, 6)
            .background(model.focusedGroup == g.id ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture { model.focusedGroup = g.id }
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func groupDetail(_ model: DuplicatesModel) -> some View {
        if let g = model.groups.first(where: { $0.id == model.focusedGroup }) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                    ForEach(g.files) { f in
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack(alignment: .topLeading) {
                                Group {
                                    if UTType(filenameExtension: f.url.pathExtension)?.conforms(to: .image) == true {
                                        ThumbnailView(url: f.url, maxPixel: 400, iconSize: 96)
                                    } else {
                                        FileIcon(url: f.url, size: 96)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 130)
                                CheckBox(state: model.marked.contains(f.id)) { model.toggle(f) }.padding(6)
                            }
                            Text(f.url.lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                            Text(f.url.deletingLastPathComponent().displayPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            HStack {
                                Text(Fmt.date(f.created)).font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                SizeLabel(bytes: f.size).font(.caption)
                                RevealButton(url: f.url)
                            }
                        }
                        .padding(10)
                        .background(model.marked.contains(f.id) ? Theme.selection : Theme.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(14)
            }
        } else {
            EmptyStateView(icon: "square.on.square", title: "Escolha um grupo")
        }
    }
}
