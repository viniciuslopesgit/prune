import SwiftUI

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @AppStorage("showMenuBar") private var showMenuBar = true
    @State private var launchAtLogin = AppSettings.shared.launchAtLogin
    @State private var hasFDA = Permissions.hasFullDiskAccess

    var body: some View {
        TabView {
            Form {
                Section("Geral") {
                    Toggle("Mostrar monitor na barra de menus", isOn: $showMenuBar)
                    Toggle("Abrir ao iniciar sessão", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, v in settings.launchAtLogin = v }
                    Toggle("A Análise Inteligente executa tarefas de manutenção", isOn: $settings.smartScanRunsMaintenance)
                    Toggle("Incluir tarefas que pedem a palavra-passe de administrador", isOn: $settings.smartScanAdminTasks)
                        .disabled(!settings.smartScanRunsMaintenance)
                        .help("Limpar DNS, espaço purgável, reindexar o Spotlight… O macOS pede a palavra-passe sempre que estas tarefas correm.")
                }
                Section("Remoção") {
                    Picker("Lixo do sistema (caches, registos)", selection: $settings.junkDeleteMode) {
                        ForEach(DeleteMode.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Ficheiros e aplicações", selection: $settings.filesDeleteMode) {
                        ForEach(DeleteMode.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("Passagens do Destruidor: \(settings.shredPasses)", value: $settings.shredPasses, in: 1...7)
                    Stepper("Tamanho mínimo em Grandes e Antigos: \(settings.largeFileMinMB) MB", value: $settings.largeFileMinMB, in: 10...5000, step: 10)
                }
                if Analytics.isAvailable {
                    Section("Estatísticas") {
                        Toggle("Partilhar estatísticas de utilização anónimas", isOn: Binding(
                            get: { settings.analyticsEnabled },
                            set: { settings.analyticsEnabled = $0; settings.analyticsAsked = true }))
                        Text(Analytics.disclosure).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Permissões") {
                    HStack {
                        Label(hasFDA ? "Acesso Total ao Disco concedido" : "Acesso Total ao Disco em falta",
                              systemImage: hasFDA ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(hasFDA ? Theme.leaf : Theme.amber)
                        Spacer()
                        Button("Abrir Definições") { Permissions.openFullDiskAccessSettings() }
                    }
                    Text("Com esta permissão o macOS deixa de pedir autorização para cada pasta (Documentos, Secretária, Transferências, dados de outras apps). Arraste o Prune para a lista em Privacidade e segurança ▸ Acesso total ao disco.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Mostrar o assistente ao abrir enquanto faltar a permissão", isOn: Binding(
                        get: { !settings.fdaOnboardingDismissed }, set: { settings.fdaOnboardingDismissed = !$0 }))
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Geral", systemImage: "gearshape") }

            Form {
                Section {
                    if settings.ignoredPaths.isEmpty {
                        Text("Nenhum item ignorado.").foregroundStyle(.secondary)
                    }
                    ForEach(settings.ignoredPaths, id: \.self) { path in
                        HStack {
                            FileIcon(url: URL(fileURLWithPath: path), size: 18)
                            Text(URL(fileURLWithPath: path).displayPath).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button { settings.ignoredPaths.removeAll { $0 == path } } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                        }
                    }
                    Button("Adicionar…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = true
                        if panel.runModal() == .OK {
                            settings.ignoredPaths += panel.urls.map(\.path).filter { !settings.ignoredPaths.contains($0) }
                        }
                    }
                } header: {
                    Text("Ficheiros e pastas que o Prune nunca vai remover")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Lista de exclusões", systemImage: "hand.raised") }
        }
        .frame(width: 560, height: 460)
        .onAppear { hasFDA = Permissions.hasFullDiskAccess }
    }
}

// MARK: - Barra de menus

struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    private var stats: SystemStats { SystemStats.shared }
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
            Text("\(Int(stats.cpu * 100))%").monospacedDigit()
        }
        .onAppear { WindowOpener.shared.action = openWindow }
    }
}

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    private var stats: SystemStats { SystemStats.shared }
    @State private var topApps: [ProcessInfoRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles").font(.title3)
                Text("Prune").font(.headline)
                Spacer()
                Text("Ligado há \(stats.uptimeText)").font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                tile("Disco", value: stats.diskUsedFraction, caption: "\(Fmt.bytes(stats.diskFree)) livres", icon: "internaldrive")
                tile("Memória", value: stats.memoryFraction, caption: Fmt.bytes(stats.memoryUsed), icon: "memorychip")
                tile("CPU", value: stats.cpu, caption: stats.thermalText, icon: "cpu")
            }

            VStack(alignment: .leading, spacing: 6) {
                Sparkline(values: stats.cpuHistory).frame(height: 36)
                HStack {
                    Label(SystemStats.speed(stats.netDown), systemImage: "arrow.down")
                    Spacer()
                    Label(SystemStats.speed(stats.netUp), systemImage: "arrow.up")
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let b = stats.battery {
                HStack {
                    Image(systemName: b.charging ? "battery.100.bolt" : "battery.75")
                    Text("\(b.percent)%").monospacedDigit()
                    if let h = b.health { Text("· saúde \(Fmt.percent(h))").foregroundStyle(.secondary) }
                    if let c = b.cycleCount { Text("· \(c) ciclos").foregroundStyle(.secondary) }
                    Spacer()
                }
                .font(.callout)
            }

            if !topApps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mais exigentes").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(topApps) { p in
                        HStack(spacing: 6) {
                            if let i = p.icon { Image(nsImage: i).resizable().frame(width: 16, height: 16) }
                            Text(p.name).lineLimit(1)
                            Spacer()
                            Text(String(format: "%.0f%%", p.cpu)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }

            Divider()
            HStack {
                Button("Análise Inteligente") {
                    state.selection = .smartScan
                    openMain()
                }
                Spacer()
                Button { openMain() } label: { Image(systemName: "macwindow") }.help("Abrir Prune")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Sair")
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(width: 340)
        .task {
            while !Task.isCancelled {
                let all = await OptimizationService.processes()
                topApps = Array(all.filter(\.isApp).sorted { $0.cpu > $1.cpu }.prefix(4))
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func openMain() {
        WindowOpener.shared.action = openWindow
        WindowOpener.shared.openMain()
    }

    private func tile(_ title: String, value: Double, caption: String, icon: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RingGauge(value: value, lineWidth: 6, color: value > 0.85 ? Theme.amber : Theme.accent)
                Text(Fmt.percent(value)).font(.caption.bold()).monospacedDigit()
            }
            .frame(width: 54, height: 54)
            Label(title, systemImage: icon).font(.caption.bold())
            Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
