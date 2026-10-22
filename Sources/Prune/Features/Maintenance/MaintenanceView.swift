import SwiftUI

struct MaintenanceView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var model = state.maintenance
        VStack(spacing: 0) {
            ModuleHeader(module: .maintenance, subtitle: "Tarefas para manter o macOS estável")
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
                                Label("Recomendado a cada \(Fmt.count(t.recommendedDays, "dia", "dias"))", systemImage: "calendar").font(.callout).foregroundStyle(.secondary)
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
            ActionFooter(summary: Fmt.count(model.selected.count, "tarefa selecionada", "tarefas selecionadas"), buttonTitle: model.running ? "A executar…" : "Executar",
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
