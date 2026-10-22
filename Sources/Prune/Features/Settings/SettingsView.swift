import SwiftUI

struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @AppStorage("showMenuBar") private var showMenuBar = true
    @State private var launchAtLogin = AppSettings.shared.launchAtLogin
    @State private var hasFDA = Permissions.hasFullDiskAccess

    var body: some View {
        TabView {
            Form {
                Section("General") {
                    Toggle("Show monitor in the menu bar", isOn: $showMenuBar)
                    Toggle("Open at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, v in settings.launchAtLogin = v }
                }
                Section("Removal") {
                    Picker("System junk (caches, logs)", selection: $settings.junkDeleteMode) {
                        ForEach(DeleteMode.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Files and applications", selection: $settings.filesDeleteMode) {
                        ForEach(DeleteMode.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("Shredder passes: \(settings.shredPasses)", value: $settings.shredPasses, in: 1...7)
                    Stepper("Minimum size in Large & Old Files: \(settings.largeFileMinMB) MB", value: $settings.largeFileMinMB, in: 10...5000, step: 10)
                }
                if Analytics.isAvailable {
                    Section("Statistics") {
                        Toggle("Share anonymous usage statistics", isOn: Binding(
                            get: { settings.analyticsEnabled },
                            set: { settings.analyticsEnabled = $0; settings.analyticsAsked = true }))
                        Text(Analytics.disclosure).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Permissions") {
                    HStack {
                        Label(hasFDA ? "Full Disk Access granted" : "Full Disk Access missing",
                              systemImage: hasFDA ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(hasFDA ? Theme.leaf : Theme.amber)
                        Spacer()
                        Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
                    }
                    Text("Without this permission, macOS asks for authorization for each protected folder.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Remind me on launch while the permission is missing", isOn: Binding(
                        get: { !settings.fdaOnboardingDismissed }, set: { settings.fdaOnboardingDismissed = !$0 }))
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section {
                    if settings.ignoredPaths.isEmpty {
                        Text("No ignored items.").foregroundStyle(.secondary)
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
                    Button("Add…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.allowsMultipleSelection = true
                        if panel.runModal() == .OK {
                            settings.ignoredPaths += panel.urls.map(\.path).filter { !settings.ignoredPaths.contains($0) }
                        }
                    }
                } header: {
                    Text("Prune never removes these files and folders")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Exclusion list", systemImage: "hand.raised") }
        }
        .frame(width: 560, height: 460)
        .onAppear { hasFDA = Permissions.hasFullDiskAccess }
    }
}
