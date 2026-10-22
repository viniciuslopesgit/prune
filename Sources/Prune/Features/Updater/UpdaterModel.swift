import AppKit
import Observation

@MainActor
@Observable
final class UpdaterModel {
    var updates: [AppUpdate] = []
    var checking = false
    var checked = false
    var progressText = ""
    var log: [String] = []
    var installing = false
    var hasBrew: Bool { UpdateService.brew != nil }

    func check() async {
        checking = true
        let reporter = ProgressReporter { [weak self] in self?.progressText = $0 }
        reporter.report("A procurar apps…", force: true)
        let apps = await Task.detached { AppScanner.installedApps(computeSizes: false) }.value
        async let sparkle = UpdateService.sparkleUpdates(apps, progress: reporter)
        reporter.report("A verificar Homebrew…")
        async let brew = UpdateService.homebrewUpdates()
        let (s, b) = await (sparkle, brew)
        // Evita duplicados: se a app é gerida pelo Homebrew, mostra só a entrada do Homebrew.
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
                log.append("A atualizar \(u.name) com Homebrew…")
                var args = ["upgrade", name]
                if u.source == .homebrew { args.insert("--cask", at: 1) }
                let r = await Shell.run(brew, args, env: ["HOMEBREW_NO_AUTO_UPDATE": "1"])
                log.append(r.ok ? "✓ \(u.name) atualizado para \(u.latest)" : "✗ \(u.name): \(r.err.split(separator: "\n").last ?? "erro")")
                if r.ok { updates.removeAll { $0.id == u.id } }
            case .sparkle:
                // A app trata da atualização através do Sparkle ao abrir; se não, abre a transferência.
                if let app = u.appURL {
                    log.append("A abrir \(u.name) para atualizar…")
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
