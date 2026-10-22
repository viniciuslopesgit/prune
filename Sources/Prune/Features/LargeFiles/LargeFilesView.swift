import SwiftUI

struct LargeFilesView: View {
    @Environment(AppState.self) private var state
    @State private var confirm: Bool = false
    @State private var shredMode = false

    var body: some View {
        @Bindable var model = state.largeFiles
        VStack(spacing: 0) {
            if model.scanning {
                ScanningView(module: .largeFiles, title: "A procurar ficheiros grandes…", detail: model.progressText)
            } else if !model.scanned {
                ModuleHeader(module: .largeFiles)
                HeroView(
                    module: .largeFiles, headline: "Encontre ficheiros grandes e esquecidos",
                    message: "Localize vídeos, imagens de disco, arquivos e documentos enormes que já não abre há muito tempo.",
                    features: [("arrow.up.right.and.arrow.down.left", "Filtre por tamanho"), ("calendar", "Filtre pela última abertura"),
                               ("square.grid.2x2", "Filtre por tipo de ficheiro")],
                    footnote: "Analisa a sua pasta pessoal\(model.includeLibrary ? ", incluindo a Biblioteca" : "")."
                ) { Task { await model.scan() } }
                Toggle("Incluir a pasta Biblioteca", isOn: $model.includeLibrary).padding(.bottom, 150)
            } else {
                ModuleHeader(module: .largeFiles, subtitle: "\(model.filtered.count) ficheiros · \(Fmt.bytes(model.filtered.reduce(0) { $0 + $1.size }))") {
                    Button { Task { await model.scan() } } label: { Label("Analisar de novo", systemImage: "arrow.clockwise") }.buttonStyle(.bordered)
                }
                filters(model)
                if let msg = model.message {
                    StatusBanner(text: msg, icon: "checkmark.circle", actionTitle: "OK") { model.message = nil }
                        .padding(.horizontal, 32).padding(.bottom, 8)
                }
                HStack(spacing: 14) {
                    GlassPanel {
                        List(FileKind.allCases) { k in
                            HStack {
                                Image(systemName: k.icon).frame(width: 22)
                                Text(k.rawValue)
                                Spacer()
                                Text("\(model.count(k))").foregroundStyle(.secondary).monospacedDigit()
                            }
                            .padding(.vertical, 4).padding(.horizontal, 6)
                            .background(model.kind == k ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .onTapGesture { model.kind = k }
                            .listRowBackground(Color.clear).listRowSeparator(.hidden)
                        }
                        .scrollContentBackground(.hidden)
                    }
                    .frame(width: 220)
                    GlassPanel {
                        List(model.filtered) { f in
                            HStack(spacing: 10) {
                                CheckBox(state: model.selected.contains(f.id)) {
                                    if model.selected.contains(f.id) { model.selected.remove(f.id) } else { model.selected.insert(f.id) }
                                }
                                FileIcon(url: f.url, size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(f.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                    Text(f.url.deletingLastPathComponent().displayPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Text("Aberto \(Fmt.relative(f.accessed ?? f.modified))").font(.caption).foregroundStyle(.secondary).frame(width: 150, alignment: .trailing)
                                SizeLabel(bytes: f.size).frame(width: 80, alignment: .trailing)
                                RevealButton(url: f.url)
                            }
                            .listRowBackground(Color.clear)
                        }
                        .scrollContentBackground(.hidden)
                        .overlay { if model.filtered.isEmpty { EmptyStateView(icon: "doc", title: "Nenhum ficheiro com estes filtros") } }
                    }
                }
                .padding(.horizontal, 32).padding(.bottom, 14)
                ActionFooter(summary: "\(model.selected.count) selecionados · \(Fmt.bytes(model.selectedSize))",
                             buttonTitle: "Remover", disabled: model.selected.isEmpty || model.working,
                             secondary: ("Destruir", { shredMode = true; confirm = true })) {
                    shredMode = false
                    confirm = true
                }
                .confirm(shredMode ? "Destruir de forma segura?" : "Remover ficheiros?", isPresented: $confirm,
                         message: shredMode ? "Os ficheiros serão sobrescritos e apagados. Não será possível recuperá-los."
                                            : (AppSettings.shared.filesDeleteMode == .trash ? "Os ficheiros serão movidos para o Lixo." : "Os ficheiros serão apagados definitivamente."),
                         button: shredMode ? "Destruir" : "Remover") {
                    Task { await model.removeSelected(shred: shredMode) }
                }
            }
        }
    }

    private func filters(_ model: LargeFilesModel) -> some View {
        @Bindable var model = model
        return HStack(spacing: 16) {
            Picker("Tamanho mínimo", selection: $model.minMB) {
                ForEach([10, 50, 100, 500, 1000, 5000], id: \.self) { Text($0 >= 1000 ? "\($0 / 1000) GB" : "\($0) MB").tag($0) }
            }
            .frame(width: 220)
            Picker("Aberto há", selection: $model.age) {
                ForEach(FileAge.allCases) { Text($0.rawValue).tag($0) }
            }
            .frame(width: 240)
            Spacer()
        }
        .padding(.horizontal, 32).padding(.bottom, 10)
    }
}
