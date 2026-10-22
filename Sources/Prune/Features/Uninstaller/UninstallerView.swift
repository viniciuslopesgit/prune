import SwiftUI

struct UninstallerView: View {
    @Environment(AppState.self) private var state
    @State private var confirmUninstall = false
    @State private var confirmReset = false
    @State private var confirmBatch = false

    var body: some View {
        @Bindable var model = state.uninstaller
        VStack(spacing: 0) {
            ModuleHeader(module: .uninstaller, subtitle: model.loaded ? "\(Fmt.count(model.apps.count, "app", "apps")) · \(Fmt.bytes(model.apps.reduce(0) { $0 + $1.size }))" : nil) {
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
                    ActionFooter(summary: "\(Fmt.count(model.checked.count, "app", "apps")) · \(Fmt.bytes(model.checked.reduce(0) { $0 + $1.size }))",
                                 buttonTitle: "Desinstalar", disabled: model.working) { confirmBatch = true }
                        .confirm("Desinstalar \(Fmt.count(model.checked.count, "app", "apps"))?", isPresented: $confirmBatch,
                                 message: "As apps e os ficheiros de suporte são removidos.", button: "Desinstalar") {
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
                        .help("Apaga preferências e dados. A app fica como nova.")
                    Button("Desinstalar") { confirmUninstall = true }
                        .buttonStyle(.borderedProminent).tint(.red.opacity(0.7)).disabled(model.working)
                }
                .padding(14)
            }
            .confirm("Desinstalar \(app.name)?", isPresented: $confirmUninstall,
                     message: "A app e os ficheiros de suporte selecionados são removidos.", button: "Desinstalar") {
                Task { await model.uninstall([app], leftoversFor: [app: model.leftovers]) }
            }
            .confirm("Repor \(app.name)?", isPresented: $confirmReset,
                     message: "As preferências e os dados são apagados. A app continua instalada.", button: "Repor") {
                Task { await model.reset(app) }
            }
        } else {
            EmptyStateView(icon: "xmark.app", title: "Escolha uma aplicação",
                           message: "Veja todos os ficheiros da app e remova-a por completo.")
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
                        Text("Ficheiros de apps que já não estão instaladas. Reveja antes de remover.")
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(.horizontal, 32).padding(.bottom, 14)
        ActionFooter(summary: "\(Fmt.bytes(model.orphans.filter(\.selected).reduce(0) { $0 + $1.size }))",
                     buttonTitle: "Remover", disabled: !model.orphans.contains(where: \.selected) || model.working) {
            Task { await model.removeOrphans() }
        }
    }
}
