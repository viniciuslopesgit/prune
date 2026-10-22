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
                    Text("Sem esta permissão, o macOS pede autorização para cada pasta protegida.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Lembrar ao abrir enquanto faltar a permissão", isOn: Binding(
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
                    Text("O Prune nunca remove estes ficheiros e pastas")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Lista de exclusões", systemImage: "hand.raised") }
        }
        .frame(width: 560, height: 460)
        .onAppear { hasFDA = Permissions.hasFullDiskAccess }
    }
}
