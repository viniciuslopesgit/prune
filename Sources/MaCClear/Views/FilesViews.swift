import SwiftUI
import UniformTypeIdentifiers

// MARK: - Grandes e Antigos

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

// MARK: - Duplicados

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
                ModuleHeader(module: .duplicates, subtitle: model.groups.isEmpty ? "Sem duplicados" : "\(model.groups.count) grupos · \(Fmt.bytes(model.wasted)) em cópias") {
                    Button("Nova análise") { model.scanned = false }.buttonStyle(.bordered)
                }
                if let msg = model.message {
                    StatusBanner(text: msg, icon: "checkmark.circle", actionTitle: "OK") { model.message = nil }
                        .padding(.horizontal, 32).padding(.bottom, 8)
                }
                if model.groups.isEmpty {
                    EmptyStateView(icon: "checkmark.circle", title: "Não há duplicados", message: "Não foram encontradas cópias nas pastas escolhidas.")
                } else {
                    HStack(spacing: 14) {
                        GlassPanel { groupList(model) }.frame(width: 340)
                        GlassPanel { groupDetail(model) }
                    }
                    .padding(.horizontal, 32).padding(.bottom, 14)
                    ActionFooter(summary: "Selecionado: \(Fmt.bytes(model.markedSize))", buttonTitle: "Remover",
                                 disabled: model.marked.isEmpty,
                                 secondary: model.mode == .exact ? ("Seleção automática", { model.autoSelect() }) : nil) { confirm = true }
                        .confirm("Remover \(model.marked.count) cópia(s)?", isPresented: $confirm,
                                 message: "Os ficheiros selecionados serão removidos.", button: "Remover") {
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
                 ? "Encontra ficheiros com conteúdo idêntico, mesmo com nomes diferentes."
                 : "Encontra fotografias parecidas (sequências, versões editadas, capturas repetidas).")
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
                        Text("\(g.files.count) cópias").font(.caption).foregroundStyle(.secondary)
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

// MARK: - Destruidor

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
                        Text("O conteúdo é sobrescrito com dados aleatórios antes de ser apagado.").foregroundStyle(.secondary)
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
            StatusBanner(text: "Em SSDs e no APFS, o sistema pode guardar cópias antigas de blocos (cópia-em-escrita, instantâneos). Para proteção total, ative o FileVault.",
                         icon: "exclamationmark.shield")
                .padding(.horizontal, 32).padding(.bottom, 10)
            ActionFooter(summary: "\(model.items.count) item(ns) · \(AppSettings.shared.shredPasses) passagem(ns)",
                         buttonTitle: model.working ? "A destruir…" : "Destruir",
                         disabled: model.items.isEmpty || model.working,
                         secondary: ("Adicionar…", { pick(model) })) { confirm = true }
                .confirm("Destruir \(model.items.count) item(ns)?", isPresented: $confirm,
                         message: "Esta ação é irreversível. Os ficheiros não poderão ser recuperados.", button: "Destruir") {
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
