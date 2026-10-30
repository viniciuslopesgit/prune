import AppKit

@MainActor
final class UninstallerModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all, unused, large, appStore, leftovers
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: String(localized: "All")
            case .unused: String(localized: "Unused")
            case .large: String(localized: "Large")
            case .appStore: "App Store"
            case .leftovers: String(localized: "Leftovers")
            }
        }
    }

    @Published var apps: [AppInfo] = []
    @Published var loading = false
    @Published var loaded = false
    @Published var filter: Filter = .all
    @Published var search = ""
    @Published var focused: AppInfo?
    @Published var leftovers: [CleanItem] = []
    @Published var loadingLeftovers = false
    @Published var checked: Set<AppInfo> = []
    @Published var orphans: [CleanItem] = []
    @Published var working = false
    @Published var message: String?

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

    /// Uninstalls the app and the selected support files.
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
        message = Fmt.freedMessage(freed, failed: failed.count)
        working = false
    }

    /// Resets the app: deletes only the support files (preferences, caches…).
    func reset(_ app: AppInfo) async {
        working = true
        await quitIfRunning(app)
        let r = await Cleaner.remove(urls: leftovers.filter(\.selected).map(\.url), mode: AppSettings.shared.filesDeleteMode)
        message = String(localized: "\(app.name) reset. \(Fmt.bytes(r.freed)) freed.")
        await focus(app)
        working = false
    }

    func removeOrphans() async {
        working = true
        let selected = orphans.filter(\.selected)
        let r = await Cleaner.remove(urls: selected.map(\.url), mode: AppSettings.shared.filesDeleteMode)
        let removed = Set(selected.map(\.url)).subtracting(r.failed)
        orphans.removeAll { removed.contains($0.url) }
        message = Fmt.freedMessage(r.freed, failed: 0)
        working = false
    }
}
