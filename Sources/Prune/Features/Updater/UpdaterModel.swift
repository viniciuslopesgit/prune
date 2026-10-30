import AppKit

@MainActor
final class UpdaterModel: ObservableObject {
    @Published var updates: [AppUpdate] = []
    @Published var checking = false
    @Published var checked = false
    @Published var progressText = ""
    @Published var log: [String] = []
    @Published var installing = false
    var hasBrew: Bool { UpdateService.brew != nil }

    func check() async {
        checking = true
        let reporter = ProgressReporter { [weak self] in self?.progressText = $0 }
        reporter.report(String(localized: "Looking for apps…"), force: true)
        let apps = await Task.detached { AppScanner.installedApps(computeSizes: false) }.value
        async let sparkle = UpdateService.sparkleUpdates(apps, progress: reporter)
        reporter.report(String(localized: "Checking Homebrew…"))
        async let brew = UpdateService.homebrewUpdates()
        let (s, b) = await (sparkle, brew)
        // Avoids duplicates: if the app is managed by Homebrew, only shows the Homebrew entry.
        let brewNames = Set(b.map { $0.name.lowercased().replacingOccurrences(of: "-", with: " ") })
        updates = b + s.filter { !brewNames.contains($0.name.lowercased()) }
        checking = false
        checked = true
    }

    func updateSelected() async {
        installing = true
        log = []
        for u in updates where u.selected {
            switch u.source {
            case .homebrew, .homebrewFormula:
                guard let brew = UpdateService.brew, let name = u.brewName else { continue }
                log.append(String(localized: "Updating \(u.name) with Homebrew…"))
                var args = ["upgrade", name]
                if u.source == .homebrew { args.insert("--cask", at: 1) }
                let r = await Shell.run(brew, args, env: ["HOMEBREW_NO_AUTO_UPDATE": "1"])
                log.append(r.ok ? String(localized: "✓ \(u.name) updated to \(u.latest)") : "✗ \(u.name): \(r.err.split(separator: "\n").last.map(String.init) ?? String(localized: "error"))")
                if r.ok { updates.removeAll { $0.id == u.id } }
            case .sparkle:
                // The app handles the update through Sparkle when it opens; otherwise, opens the download.
                if let app = u.appURL {
                    log.append(String(localized: "Opening \(u.name) to update…"))
                    NSWorkspace.shared.openApplication(at: app, configuration: .init()) { _, _ in }
                } else if let d = u.downloadURL {
                    NSWorkspace.shared.open(d)
                }
            }
        }
        installing = false
    }

    func openAppStoreUpdates() {
        if let url = URL(string: "macappstore://showUpdatesPage") { NSWorkspace.shared.open(url) }
    }
}
