import SwiftUI

struct MaintenanceView: View {
    private var state: AppState { .shared }
    @ObservedObject private var model = AppState.shared.maintenance

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .maintenance, subtitle: String(localized: "Tasks to keep macOS stable"))
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
                                                .help("Asks for the administrator password")
                                        }
                                    }
                                    Text("Last run: \(Fmt.relative(model.lastRun(t.id)))").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                stateIcon(model.states[t.id])
                            }
                            .padding(.vertical, 3).padding(.horizontal, 6)
                            .background(model.focused == t.id ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .onTapGesture { model.focused = t.id }
                            .listRowBackground(Color.clear)
                            .hiddenRowSeparator()
                        }
                    }
                    .hiddenScrollBackground()
                }
                .frame(width: 360)

                GlassPanel {
                    if let t = MaintenanceCatalog.tasks.first(where: { $0.id == model.focused }) {
                        VStack(alignment: .leading, spacing: 14) {
                            Image(systemName: t.icon).font(.system(size: 54)).symbolRenderingMode(.hierarchical)
                            Text(t.title).font(.title.bold())
                            Text(t.description).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            if t.requiresAdmin {
                                Label("Requires the administrator password", systemImage: "lock").font(.callout).foregroundStyle(.secondary)
                            }
                            if t.recommendedDays > 0 {
                                Label("Recommended every \(Fmt.count(t.recommendedDays, String(localized: "day"), String(localized: "days")))", systemImage: "calendar").font(.callout).foregroundStyle(.secondary)
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
            ActionFooter(summary: Fmt.count(model.selected.count, String(localized: "task selected"), String(localized: "tasks selected")),
                         buttonTitle: model.running ? String(localized: "Running…") : String(localized: "Run"),
                         disabled: model.selected.isEmpty || model.running,
                         secondary: (String(localized: "Recommended"), { model.selected = Set(model.recommended.filter { !$0.requiresAdmin }.map(\.id)) })) {
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
