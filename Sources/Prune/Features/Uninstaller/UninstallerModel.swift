import AppKit
import Observation

@MainActor
@Observable
final class UninstallerModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "Todas", unused = "Não usadas", large = "Grandes", appStore = "App Store", leftovers = "Restos"
        var id: String { rawValue }
    }

    var apps: [AppInfo] = []
    var loading = false
    var loaded = false
    var filter: Filter = .all
    var search = ""
    var focused: AppInfo?
    var leftovers: [CleanItem] = []
    var loadingLeftovers = false
    var checked: Set<AppInfo> = []
    var orphans: [CleanItem] = []
    var working = false
    var message: String?

    func load() async {
        loading = true
        apps = await Task.detached { AppScanner.installedApps() }.value
        loading = false
        loaded = true
        let installedIDs = Set(apps.map(\.bundleID))
        let systemIDs = await AppScanner.allSystemBundleIDs()
        orphans = await Task.detached { AppScanner.orphans(installedIDs: installedIDs.union(systemIDs)) }.value
    }

    func releaseDetails() {
        focused = nil
        leftovers = []
    }

    var filtered: [AppInfo] {
        var list = apps
        switch filter {
        case .all, .leftovers: break
        case .unused:
            let cutoff = Date().addingTimeInterval(-90 * 86400)
            list = list.filter { ($0.lastUsed ?? .distantPast) < cutoff }
        case .large: list = list.sorted { $0.size > $1.size }.filter { $0.size > 500_000_000 }
        case .appStore: list = list.filter(\.isAppStore)
        }
        if !search.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
        }
        return list
    }

    func focus(_ app: AppInfo) async {
        focused = app
        loadingLeftovers = true
        leftovers = await Task.detached { AppScanner.leftovers(for: app) }.value
        loadingLeftovers = false
    }

    private func quitIfRunning(_ app: AppInfo) async {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID)
        guard !running.isEmpty else { return }
        running.forEach { $0.terminate() }
        for _ in 0..<20 where running.contains(where: { !$0.isTerminated }) { await Task.pause(0.25) }
        running.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
    }

    /// Desinstala a app e os ficheiros de suporte selecionados.
    func uninstall(_ targets: [AppInfo], leftoversFor: [AppInfo: [CleanItem]]) async {
        working = true
        var failed: [URL] = []
        var freed: Int64 = 0
        let mode = AppSettings.shared.filesDeleteMode
        for app in targets {
            await quitIfRunning(app)
            var extra = leftoversFor[app] ?? []
            if leftoversFor[app] == nil { extra = await Task.detached { AppScanner.leftovers(for: app) }.value }
            for agent in extra where agent.url.path.contains("LaunchAgents") && agent.url.path.hasPrefix(home.path) {
                _ = await Shell.run("/bin/launchctl", ["bootout", "gui/\(Shell.uid)", agent.url.path])
            }
            let urls = [app.url] + extra.filter(\.selected).map(\.url)
            let r = await Cleaner.remove(urls: urls, mode: mode)
            freed += r.freed
            failed += r.failed
        }
        if !failed.isEmpty {
            let r = await Cleaner.retryAsAdmin(failed, mode: mode)
            freed += r.freed
            failed = r.failed
        }
        let removedApps = Set(targets.filter { !failed.contains($0.url) })
        apps.removeAll { removedApps.contains($0) }
        checked.subtract(removedApps)
        if let f = focused, removedApps.contains(f) { focused = nil; leftovers = [] }
        message = failed.isEmpty
            ? "Removido: \(Fmt.bytes(freed))."
            : "Removido \(Fmt.bytes(freed)). \(failed.count) item(ns) não puderam ser removidos."
        working = false
    }

    /// Repõe a app: apaga apenas os ficheiros de suporte (preferências, caches…).
    func reset(_ app: AppInfo) async {
        working = true
        await quitIfRunning(app)
        let r = await Cleaner.remove(urls: leftovers.filter(\.selected).map(\.url), mode: AppSettings.shared.filesDeleteMode)
        message = "\(app.name) foi reposta (\(Fmt.bytes(r.freed)) removidos)."
        await focus(app)
        working = false
    }

    func removeOrphans() async {
        working = true
        let selected = orphans.filter(\.selected)
        let r = await Cleaner.remove(urls: selected.map(\.url), mode: AppSettings.shared.filesDeleteMode)
        let removed = Set(selected.map(\.url)).subtracting(r.failed)
        orphans.removeAll { removed.contains($0.url) }
        message = "Restos removidos: \(Fmt.bytes(r.freed))."
        working = false
    }
}
