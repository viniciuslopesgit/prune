import SwiftUI

struct UninstallerView: View {
    @Environment(AppState.self) private var state
    @State private var confirmUninstall = false
    @State private var confirmReset = false
    @State private var confirmBatch = false

    var body: some View {
        @Bindable var model = state.uninstaller
        VStack(spacing: 0) {
            ModuleHeader(module: .uninstaller, subtitle: model.loaded ? "\(model.apps.count) apps · \(Fmt.bytes(model.apps.reduce(0) { $0 + $1.size }))" : nil) {
                TextField("Procurar", text: $model.search).textFieldStyle(.roundedBorder).frame(width: 200)
                Button { Task { await model.load() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.bordered)
            }
            Picker("", selection: $model.filter) {
                ForEach(UninstallerModel.Filter.allCases) { f in
                    Text(f == .leftovers && !model.orphans.isEmpty ? "\(f.rawValue) (\(model.orphans.count))" : f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented).labelsHidden().padding(.horizontal, 32).padding(.bottom, 10)

            if let msg = model.message {
                StatusBanner(text: msg, icon: "checkmark.circle", actionTitle: "OK") { model.message = nil }
                    .padding(.horizontal, 32).padding(.bottom, 8)
            }

            if model.loading {
                ScanningView(module: .uninstaller, title: "A procurar aplicações…", detail: "")
            } else if model.filter == .leftovers {
                orphans(model)
            } else {
                HStack(spacing: 14) {
                    GlassPanel { appList(model) }.frame(minWidth: 380)
                    GlassPanel { detail(model) }
                }
                .padding(.horizontal, 32).padding(.bottom, 14)
                if !model.checked.isEmpty {
                    ActionFooter(summary: "\(model.checked.count) app(s) · \(Fmt.bytes(model.checked.reduce(0) { $0 + $1.size }))",
                                 buttonTitle: "Desinstalar", disabled: model.working) { confirmBatch = true }
                        .confirm("Desinstalar \(model.checked.count) app(s)?", isPresented: $confirmBatch,
                                 message: "As apps e todos os ficheiros de suporte serão removidos.", button: "Desinstalar") {
                            Task { await model.uninstall(Array(model.checked), leftoversFor: [:]) }
                        }
                }
            }
        }
        .task { if !model.loaded { await model.load() } }
    }

    private func appList(_ model: UninstallerModel) -> some View {
        List(model.filtered) { app in
            HStack(spacing: 10) {
                CheckBox(state: model.checked.contains(app)) {
                    if model.checked.contains(app) { model.checked.remove(app) } else { model.checked.insert(app) }
                }
                FileIcon(url: app.url, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(app.name).lineLimit(1)
                        if app.isAppStore { Pill(text: "App Store") }
                    }
                    Text("Usada \(Fmt.relative(app.lastUsed))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                SizeLabel(bytes: app.size).font(.callout)
            }
            .padding(.vertical, 3).padding(.horizontal, 6)
            .background(model.focused == app ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture { Task { await model.focus(app) } }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func detail(_ model: UninstallerModel) -> some View {
        @Bindable var model = model
        if let app = model.focused {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    FileIcon(url: app.url, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).font(.title2.bold())
                        Text("Versão \(app.version) · \(app.vendor)").foregroundStyle(.secondary)
                        Text(app.bundleID).font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(18)
                Divider().opacity(0.3)
                if model.loadingLeftovers {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section("Aplicação") {
                            HStack {
                                FileIcon(url: app.url, size: 22)
                                Text(app.url.lastPathComponent)
                                Spacer()
                                SizeLabel(bytes: app.size)
                                RevealButton(url: app.url)
                            }
                            .listRowBackground(Color.clear)
                        }
                        Section("Ficheiros de suporte (\(model.leftovers.count))") {
                            ForEach($model.leftovers) { $item in
                                HStack {
                                    CheckBox(state: item.selected) { item.selected.toggle() }
                                    FileIcon(url: item.url, size: 22)
                                    VStack(alignment: .leading) {
                                        Text(item.name).lineLimit(1)
                                        Text(item.detail ?? "").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    SizeLabel(bytes: item.size)
                                    RevealButton(url: item.url)
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
                Divider().opacity(0.3)
                HStack {
                    let extra = model.leftovers.filter(\.selected).reduce(0) { $0 + $1.size }
                    Text("Total: \(Fmt.bytes(app.size + extra))").font(.headline)
                    Spacer()
                    Button("Repor") { confirmReset = true }
                        .buttonStyle(.bordered).disabled(model.leftovers.filter(\.selected).isEmpty || model.working)
                        .help("Apaga apenas preferências e dados, mantendo a app — como se fosse a primeira vez")
                    Button("Desinstalar") { confirmUninstall = true }
                        .buttonStyle(.borderedProminent).tint(.red.opacity(0.7)).disabled(model.working)
                }
                .padding(14)
            }
            .confirm("Desinstalar \(app.name)?", isPresented: $confirmUninstall,
                     message: "A app e os ficheiros de suporte selecionados serão removidos.", button: "Desinstalar") {
                Task { await model.uninstall([app], leftoversFor: [app: model.leftovers]) }
            }
            .confirm("Repor \(app.name)?", isPresented: $confirmReset,
                     message: "As preferências e dados da app serão apagados. A app mantém-se instalada.", button: "Repor") {
                Task { await model.reset(app) }
            }
        } else {
            EmptyStateView(icon: "xmark.app", title: "Escolha uma aplicação",
                           message: "Veja todos os ficheiros que a app espalhou pelo sistema e remova-os por completo.")
        }
    }

    @ViewBuilder
    private func orphans(_ model: UninstallerModel) -> some View {
        @Bindable var model = model
        GlassPanel {
            if model.orphans.isEmpty {
                EmptyStateView(icon: "checkmark.circle", title: "Sem restos de apps removidas")
            } else {
                List {
                    Section {
                        ForEach($model.orphans) { $item in
                            HStack {
                                CheckBox(state: item.selected) { item.selected.toggle() }
                                FileIcon(url: item.url, size: 22)
                                VStack(alignment: .leading) {
                                    Text(item.name).lineLimit(1)
                                    Text(item.detail ?? "").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                SizeLabel(bytes: item.size)
                                RevealButton(url: item.url)
                            }
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        Text("Ficheiros cujo identificador não corresponde a nenhuma app instalada. Reveja antes de remover.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal, 32).padding(.bottom, 14)
        ActionFooter(summary: "Selecionado: \(Fmt.bytes(model.orphans.filter(\.selected).reduce(0) { $0 + $1.size }))",
                     buttonTitle: "Remover", disabled: !model.orphans.contains(where: \.selected) || model.working) {
            Task { await model.removeOrphans() }
        }
    }
}

// MARK: - Atualizador

struct UpdaterView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var model = state.updater
        VStack(spacing: 0) {
            if model.checking {
                ScanningView(module: .updater, title: "A procurar atualizações…", detail: model.progressText)
            } else if !model.checked {
                ModuleHeader(module: .updater)
                HeroView(
                    module: .updater, headline: "Mantenha as apps atualizadas",
                    message: "Verifica as apps que se atualizam pelo site do programador (Sparkle) e os pacotes do Homebrew.",
                    features: [("globe", "Apps descarregadas da Internet"), ("mug", model.hasBrew ? "Apps e ferramentas do Homebrew" : "Homebrew (não instalado)"),
                               ("bag", "Atalho para atualizações da App Store")],
                    buttonTitle: "Verificar"
                ) { Task { await model.check() } }
            } else {
                ModuleHeader(module: .updater, subtitle: model.updates.isEmpty ? "Tudo atualizado" : "\(model.updates.count) atualização(ões) disponível(eis)") {
                    Button("App Store") { model.openAppStoreUpdates() }.buttonStyle(.bordered)
                    Button { Task { await model.check() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.bordered)
                }
                GlassPanel {
                    if model.updates.isEmpty {
                        EmptyStateView(icon: "checkmark.seal", title: "Todas as apps estão atualizadas",
                                       message: "As apps da App Store são atualizadas na própria App Store.")
                    } else {
                        List {
                            ForEach($model.updates) { $u in
                                HStack(spacing: 10) {
                                    CheckBox(state: u.selected) { u.selected.toggle() }
                                    if let app = u.appURL { FileIcon(url: app, size: 32) } else { Image(systemName: "shippingbox").font(.title2).frame(width: 32) }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(u.name).font(.headline)
                                        Text("\(u.current) → \(u.latest)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Pill(text: u.source.rawValue)
                                    if let notes = u.notesURL {
                                        Link("Novidades", destination: notes).font(.caption)
                                    }
                                }
                                .padding(.vertical, 3)
                                .listRowBackground(Color.clear)
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
                .padding(.horizontal, 32).padding(.bottom, 10)
                if !model.log.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading) { ForEach(model.log, id: \.self) { Text($0).font(.caption.monospaced()) } }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 70).padding(.horizontal, 32)
                }
                ActionFooter(summary: "\(model.updates.filter(\.selected).count) selecionada(s)",
                             buttonTitle: model.installing ? "A atualizar…" : "Atualizar",
                             disabled: model.installing || !model.updates.contains(where: \.selected)) {
                    Task { await model.updateSelected() }
                }
            }
        }
    }
}

// MARK: - Extensões

struct ExtensionsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var model = state.extensions
        VStack(spacing: 0) {
            ModuleHeader(module: .extensions, subtitle: "Extensões, plug-ins e widgets instalados") {
                Toggle("Mostrar do sistema", isOn: $model.showSystem).toggleStyle(.switch)
                Button { Task { await model.load() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.bordered)
            }
            if let msg = model.message {
                StatusBanner(text: msg, icon: "exclamationmark.triangle", actionTitle: "OK") { model.message = nil }
                    .padding(.horizontal, 32).padding(.bottom, 8)
            }
            HStack(spacing: 14) {
                GlassPanel {
                    List(ExtensionCategory.allCases) { cat in
                        HStack {
                            Image(systemName: cat.icon).frame(width: 22)
                            Text(cat.rawValue)
                            Spacer()
                            Text("\(model.count(cat))").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.vertical, 4).padding(.horizontal, 6)
                        .background(model.category == cat ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onTapGesture { model.category = cat }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .scrollContentBackground(.hidden)
                }
                .frame(width: 260)
                GlassPanel {
                    if model.loading && !model.loaded {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        content(model)
                    }
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 20)
        }
        .task { if !model.loaded { await model.load() } }
    }

    @ViewBuilder
    private func content(_ model: ExtensionsModel) -> some View {
        let cat = model.category
        if cat == .browsers {
            if model.browser.isEmpty {
                EmptyStateView(icon: "globe", title: "Sem extensões noutros navegadores")
            } else {
                List(model.browser) { ext in
                    HStack(spacing: 10) {
                        Image(systemName: "puzzlepiece.extension").frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(ext.name).lineLimit(1)
                                if !ext.fromStore { Pill(text: "Fora da loja", color: Theme.amber) }
                            }
                            Text("\(ext.browser) · v\(ext.version)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        RevealButton(url: ext.url)
                        Button("Remover") { Task { await model.remove(ext) } }.buttonStyle(.bordered)
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
        } else {
            let exts = model.extensions(in: cat)
            let files = model.files[cat] ?? []
            if exts.isEmpty && files.isEmpty {
                EmptyStateView(icon: cat.icon, title: "Nada instalado nesta categoria",
                               message: model.showSystem ? nil : "Ative \"Mostrar do sistema\" para ver também as extensões da Apple.")
            } else {
                List {
                    if !exts.isEmpty {
                        Section("Extensões de apps") {
                            ForEach(exts) { ext in
                                HStack(spacing: 10) {
                                    if let range = ext.path.range(of: ".app/") {
                                        FileIcon(url: URL(fileURLWithPath: String(ext.path[..<range.lowerBound]) + ".app"), size: 26)
                                    } else {
                                        Image(systemName: cat.icon).frame(width: 26)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(ext.name).lineLimit(1)
                                        Text(ext.parent.map { "\($0) · \(ext.identifier)" } ?? ext.identifier)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(get: { ext.enabled }, set: { _ in Task { await model.toggle(ext) } }))
                                        .toggleStyle(.switch).labelsHidden()
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    if !files.isEmpty {
                        Section("Plug-ins") {
                            ForEach(files) { f in
                                HStack(spacing: 10) {
                                    FileIcon(url: f.url, size: 26)
                                    VStack(alignment: .leading) {
                                        Text(f.url.deletingPathExtension().lastPathComponent)
                                        Text("\(f.kind) · \(f.url.deletingLastPathComponent().displayPath)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    SizeLabel(bytes: f.size)
                                    RevealButton(url: f.url)
                                    Button("Remover") { Task { await model.remove(f, category: cat) } }.buttonStyle(.bordered)
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }
}
