import SwiftUI

// MARK: - Otimização

struct OptimizationView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var model = state.optimization
        VStack(spacing: 0) {
            ModuleHeader(module: .optimization, subtitle: "Controle o que arranca com o Mac e o que consome recursos") {
                Button { Task { await model.load() } } label: { Label("Atualizar", systemImage: "arrow.clockwise") }.buttonStyle(.bordered)
            }
            Picker("", selection: $model.tab) {
                ForEach(OptimizationModel.Tab.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .padding(.horizontal, 32).padding(.bottom, 12)

            if let msg = model.message {
                StatusBanner(text: msg, icon: "exclamationmark.triangle", actionTitle: "OK") { model.message = nil }
                    .padding(.horizontal, 32).padding(.bottom, 8)
            }

            GlassPanel {
                if model.loading && !model.loaded {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch model.tab {
                    case .loginItems: loginItems(model)
                    case .agents: agents(model)
                    case .heavy: heavy(model)
                    }
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 20)
        }
        .task { if !model.loaded { await model.load() } }
        .task(id: model.tab) {
            while model.tab == .heavy && !Task.isCancelled {
                await model.refreshProcesses()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func loginItems(_ model: OptimizationModel) -> some View {
        VStack(spacing: 0) {
            if model.loadingLoginItems && model.loginItems.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("A pedir a lista ao macOS… Se aparecer um pedido de autorização para \"System Events\", aceite-o.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else if model.loginItems.isEmpty {
                EmptyStateView(icon: "person.badge.key", title: "Sem itens de início de sessão",
                               message: "Não foram encontradas apps que abram automaticamente (pode ser preciso autorizar o acesso a \"System Events\").")
            } else {
                List(model.loginItems) { item in
                    HStack(spacing: 10) {
                        FileIcon(url: URL(fileURLWithPath: item.path))
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text(item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button("Remover") { Task { await model.remove(item) } }.buttonStyle(.bordered)
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
            Divider().opacity(0.3)
            HStack {
                Text("Itens em segundo plano geridos pelo macOS aparecem nas Definições do Sistema.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Abrir Definições") { Permissions.openLoginItemsSettings() }.buttonStyle(.bordered)
            }
            .padding(12)
        }
    }

    private func agents(_ model: OptimizationModel) -> some View {
        List(model.launchItems) { item in
            HStack(spacing: 10) {
                Image(systemName: item.domain == .daemon ? "gearshape.2" : "bolt.horizontal").frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.ownerName).font(.headline)
                        Pill(text: item.domain.rawValue)
                        if item.programMissing { Pill(text: "Órfão", color: Theme.amber) }
                        if item.loaded && !item.disabled { Pill(text: "Ativo", color: Theme.leaf) }
                    }
                    Text(item.label).font(.caption).foregroundStyle(.secondary)
                    if let p = item.program {
                        Text(p).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(get: { !item.disabled }, set: { _ in Task { await model.toggle(item) } }))
                    .toggleStyle(.switch).labelsHidden()
                    .help(item.disabled ? "Ativar" : "Desativar")
                Menu {
                    Button("Mostrar no Finder") { FS.reveal(item.url) }
                    Button("Remover", role: .destructive) { Task { await model.remove(item) } }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).frame(width: 30)
            }
            .padding(.vertical, 3)
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .overlay {
            if model.launchItems.isEmpty { EmptyStateView(icon: "bolt.slash", title: "Sem agentes de arranque de terceiros") }
        }
    }

    private func heavy(_ model: OptimizationModel) -> some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            HStack {
                Picker("Ordenar por", selection: $model.sortByMemory) {
                    Text("Processador").tag(false)
                    Text("Memória").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 260)
                Spacer()
                Text("Atualizado a cada 3 s").font(.caption).foregroundStyle(.secondary)
            }
            .padding(12)
            List(model.topProcesses) { p in
                HStack(spacing: 10) {
                    if let icon = p.icon { Image(nsImage: icon).resizable().frame(width: 24, height: 24) }
                    else { Image(systemName: "gearshape").frame(width: 24) }
                    VStack(alignment: .leading) {
                        Text(p.name).lineLimit(1)
                        Text("PID \(p.pid) · \(p.user)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%.1f%%", p.cpu)).monospacedDigit().frame(width: 70, alignment: .trailing)
                    // Só métricas: o macOS gere a memória sozinho, por isso o Prune não fecha apps para a "libertar".
                    Text(Fmt.bytes(p.memory)).monospacedDigit().foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - Manutenção

struct MaintenanceView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var model = state.maintenance
        VStack(spacing: 0) {
            ModuleHeader(module: .maintenance, subtitle: "Tarefas que mantêm o macOS rápido e estável")
            HStack(spacing: 14) {
                GlassPanel {
                    List {
                        ForEach(MaintenanceCatalog.tasks) { t in
                            HStack(spacing: 10) {
                                CheckBox(state: model.selected.contains(t.id)) {
                                    if model.selected.contains(t.id) { model.selected.remove(t.id) } else { model.selected.insert(t.id) }
                                }
                                Image(systemName: t.icon).frame(width: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 5) {
                                        Text(t.title)
                                        if t.requiresAdmin {
                                            Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                                                .help("Pede a palavra-passe de administrador")
                                        }
                                    }
                                    Text("Última execução: \(Fmt.relative(model.lastRun(t.id)))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                stateIcon(model.states[t.id])
                            }
                            .padding(.vertical, 3).padding(.horizontal, 6)
                            .background(model.focused == t.id ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .onTapGesture { model.focused = t.id }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
                .frame(width: 360)

                GlassPanel {
                    if let t = MaintenanceCatalog.tasks.first(where: { $0.id == model.focused }) {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: t.icon).font(.system(size: 54)).symbolRenderingMode(.hierarchical)
                            Text(t.title).font(.title.bold())
                            Text(t.description).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if t.requiresAdmin {
                                Label("Requer a palavra-passe de administrador", systemImage: "lock").font(.callout).foregroundStyle(.secondary)
                            }
                            if t.recommendedDays > 0 {
                                Label("Recomendado a cada \(t.recommendedDays) dia(s)", systemImage: "calendar").font(.callout).foregroundStyle(.secondary)
                            }
                            if case .failed(let e) = model.states[t.id] {
                                Label(e, systemImage: "xmark.octagon").foregroundStyle(Theme.amber)
                            }
                            Spacer()
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 14)
            ActionFooter(summary: "\(model.selected.count) tarefa(s) selecionada(s)", buttonTitle: model.running ? "A executar…" : "Executar",
                         disabled: model.selected.isEmpty || model.running,
                         secondary: ("Recomendadas", { model.selected = Set(model.recommended.filter { !$0.requiresAdmin }.map(\.id)) })) {
                Task { await model.run(model.selected) }
            }
        }
    }

    @ViewBuilder
    private func stateIcon(_ s: MaintenanceModel.TaskState?) -> some View {
        switch s {
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.leaf)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.amber)
        default: EmptyView()
        }
    }
}
