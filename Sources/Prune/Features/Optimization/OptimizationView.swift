import SwiftUI

struct OptimizationView: View {
    private var state: AppState { .shared }
    @ObservedObject private var model = AppState.shared.optimization

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .optimization, subtitle: String(localized: "What starts with your Mac and what uses resources")) {
                Button { Task { await model.load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(.bordered)
            }
            Picker("", selection: $model.tab) {
                ForEach(OptimizationModel.Tab.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
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
                    Text("Loading… If macOS asks for access to \"System Events\", accept.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            } else if model.loginItems.isEmpty {
                EmptyStateView(icon: "person.badge.key", title: String(localized: "No login items"),
                               message: String(localized: "No app opens automatically. If you expected to see one, allow access to \"System Events\"."))
            } else {
                List(model.loginItems) { item in
                    HStack(spacing: 10) {
                        FileIcon(url: URL(fileURLWithPath: item.path))
                        VStack(alignment: .leading) {
                            Text(item.name)
                            Text(item.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button("Remove") { Task { await model.remove(item) } }.buttonStyle(.bordered)
                    }
                    .listRowBackground(Color.clear)
                }
                .hiddenScrollBackground()
            }
            Divider().opacity(0.3)
            HStack {
                Text("macOS background items are in System Settings.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Open Settings") { Permissions.openLoginItemsSettings() }.buttonStyle(.bordered)
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
                        Pill(text: item.domain.title)
                        if item.programMissing { Pill(text: String(localized: "Orphaned"), color: Theme.amber) }
                        if item.loaded && !item.disabled { Pill(text: String(localized: "Active"), color: Theme.leaf) }
                    }
                    Text(item.label).font(.caption).foregroundStyle(.secondary)
                    if let p = item.program {
                        Text(p).font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer()
                Toggle("", isOn: Binding(get: { !item.disabled }, set: { _ in Task { await model.toggle(item) } }))
                    .toggleStyle(.switch).labelsHidden()
                    .help(item.disabled ? "Enable" : "Disable")
                Menu {
                    Button("Show in Finder") { FS.reveal(item.url) }
                    Button("Remove", role: .destructive) { Task { await model.remove(item) } }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).frame(width: 30)
            }
            .padding(.vertical, 3)
            .listRowBackground(Color.clear)
        }
        .hiddenScrollBackground()
        .overlay {
            if model.launchItems.isEmpty { EmptyStateView(icon: "bolt.slash", title: String(localized: "No third-party launch agents")) }
        }
    }

    private func heavy(_ model: OptimizationModel) -> some View {
        return VStack(spacing: 0) {
            HStack {
                Picker("Sort by", selection: $model.sortByMemory) {
                    Text("Processor").tag(false)
                    Text("Memory").tag(true)
                }
                .pickerStyle(.segmented).frame(width: 260)
                Spacer()
                Text("Updated every 3 s").font(.caption).foregroundStyle(.secondary)
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
                    // Metrics only: macOS manages memory on its own, so Prune does not quit apps to "free" it.
                    Text(Fmt.bytes(p.memory)).monospacedDigit().foregroundStyle(.secondary).frame(width: 90, alignment: .trailing)
                }
                .listRowBackground(Color.clear)
            }
            .hiddenScrollBackground()
        }
    }
}
