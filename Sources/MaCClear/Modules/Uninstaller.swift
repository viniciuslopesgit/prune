import AppKit
import Foundation
import Observation

struct AppInfo: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    let version: String
    let build: String
    var size: Int64
    let lastUsed: Date?
    let isAppStore: Bool
    let vendor: String
    let feedURL: String?

    static func == (a: AppInfo, b: AppInfo) -> Bool { a.url == b.url }
    func hash(into h: inout Hasher) { h.combine(url) }
}

enum AppScanner {
    static var appFolders: [URL] {
        [URL(fileURLWithPath: "/Applications"), URL.home("Applications"), URL(fileURLWithPath: "/Applications/Utilities")]
    }

    /// Lista as apps instaladas pelo utilizador (exclui as apps do sistema da Apple).
    static func installedApps(includeApple: Bool = false, computeSizes: Bool = true) -> [AppInfo] {
        var urls: [URL] = []
        for folder in appFolders {
            for child in FS.children(folder) {
                if child.pathExtension == "app" {
                    urls.append(child)
                } else if child.isDirectory, !child.isPackage, folder.lastPathComponent == "Applications" {
                    // Apps dentro de subpastas (ex.: /Applications/Adobe Photoshop/…)
                    urls += FS.children(child).filter { $0.pathExtension == "app" }
                }
            }
        }
        var seen = Set<String>()
        urls = urls.filter { seen.insert($0.resolvingSymlinksInPath().path).inserted }
        let sizes = computeSizes ? FS.sizes(of: urls) : Array(repeating: 0, count: urls.count)
        let lastUsedDates = lastUsed()
        var apps: [AppInfo] = []
        for (url, size) in zip(urls, sizes) {
            // Os dados do Spotlight e do plist de cada app são libertados antes da seguinte.
            autoreleasepool {
                guard let info = BundleInfo.plist(url), let id = info["CFBundleIdentifier"] as? String else { return }
                if !includeApple && id.hasPrefix("com.apple.") { return }
                let lastUsed = lastUsedDates[url.resolvingSymlinksInPath().path] ?? lastUsedDates[url.path]
                let name = (info["CFBundleDisplayName"] as? String) ?? url.deletingPathExtension().lastPathComponent
                apps.append(AppInfo(
                    url: url, name: name, bundleID: id,
                    version: info["CFBundleShortVersionString"] as? String ?? "",
                    build: info["CFBundleVersion"] as? String ?? "",
                    size: size, lastUsed: lastUsed,
                    isAppStore: url.appendingPathComponent("Contents/_MASReceipt").exists,
                    vendor: vendor(from: id),
                    feedURL: info["SUFeedURL"] as? String
                ))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Datas de última utilização de todas as apps numa só consulta ao Spotlight
    /// (criar um NSMetadataItem por app é lento e deixa ~30 MB de dados temporários).
    static func lastUsed() -> [String: Date] {
        let r = Shell.runSync("/usr/bin/mdfind", ["-attr", "kMDItemLastUsedDate", "kMDItemContentType == 'com.apple.application-bundle'"])
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        var result: [String: Date] = [:]
        for line in r.out.split(separator: "\n") {
            guard let range = line.range(of: "kMDItemLastUsedDate = ") else { continue }
            let path = line[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            if let date = f.date(from: line[range.upperBound...].trimmingCharacters(in: .whitespaces)) {
                result[path] = date
            }
        }
        return result
    }

    static func vendor(from bundleID: String) -> String {
        let parts = bundleID.split(separator: ".")
        return parts.count >= 2 ? String(parts[1]).capitalized : bundleID
    }

    static let leftoverLocations: [String] = [
        "~/Library/Application Support", "~/Library/Caches", "~/Library/Preferences", "~/Library/Preferences/ByHost",
        "~/Library/Containers", "~/Library/Group Containers", "~/Library/Saved Application State", "~/Library/Logs",
        "~/Library/HTTPStorages", "~/Library/WebKit", "~/Library/Cookies", "~/Library/LaunchAgents",
        "~/Library/Application Scripts", "~/Library/Internet Plug-Ins", "~/Library/Logs/DiagnosticReports",
        "/Library/Application Support", "/Library/Caches", "/Library/Preferences", "/Library/LaunchAgents",
        "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools", "/Library/Logs", "/Library/Internet Plug-Ins",
        "/Library/Logs/DiagnosticReports",
    ]

    static func expand(_ p: String) -> URL {
        URL(fileURLWithPath: p.hasPrefix("~") ? home.path + p.dropFirst() : p)
    }

    /// Ficheiros de suporte que a app espalhou pelo sistema.
    static func leftovers(for app: AppInfo) -> [CleanItem] {
        let id = app.bundleID.lowercased()
        let names = Set([app.name, app.url.deletingPathExtension().lastPathComponent]
            .map { $0.lowercased() }
            .flatMap { [$0, $0.replacingOccurrences(of: " ", with: "")] }
            .filter { $0.count >= 4 })
        var found: [URL] = []
        for loc in leftoverLocations {
            for entry in FS.children(expand(loc)) {
                let n = entry.lastPathComponent.lowercased()
                let stem = (n as NSString).deletingPathExtension
                let byID = n.contains(id) || stem.hasSuffix("." + id)
                let byName = names.contains(stem) || names.contains(n)
                if byID || byName { found.append(entry) }
            }
        }
        found = found.filter { SafetyGuard.canDelete($0) }
        let sizes = FS.sizes(of: found)
        return zip(found, sizes).map { url, size in
            CleanItem(url: url, size: max(size, 1), selected: true, detail: url.deletingLastPathComponent().displayPath)
        }.sorted { $0.size > $1.size }
    }

    /// Restos de apps que já foram removidas (pastas com nome de bundle ID sem app correspondente).
    static func orphans(installedIDs: Set<String>) -> [CleanItem] {
        var locations = ["~/Library/Application Support", "~/Library/Caches", "~/Library/Preferences",
                         "~/Library/Saved Application State", "~/Library/HTTPStorages",
                         "~/Library/WebKit", "~/Library/Logs"]
        // Esta análise corre sozinha ao abrir o Desinstalador. Ler dentro dos contentores de outras apps
        // faz o macOS pedir autorização, por isso só os incluímos com Acesso Total ao Disco.
        if Permissions.hasFullDiskAccess { locations.append("~/Library/Containers") }
        let installed = installedIDs.map { $0.lowercased() }
        // Programadores com alguma app instalada (ex.: com.adobe) — os seus ficheiros não são tratados como órfãos.
        let vendors = Set(installed.compactMap { id -> String? in
            let p = id.split(separator: ".")
            return p.count >= 2 ? "\(p[0]).\(p[1])" : nil
        })
        let pattern = try! NSRegularExpression(pattern: "^[a-z0-9-]+\\.[a-z0-9-]+\\.[a-z0-9.-]+$", options: [.caseInsensitive])
        var urls: [URL] = []
        for loc in locations {
            for entry in FS.children(expand(loc)) {
                var stem = entry.lastPathComponent
                for ext in [".plist", ".savedState", ".binarycookies"] where stem.hasSuffix(ext) {
                    stem = String(stem.dropLast(ext.count))
                }
                let lower = stem.lowercased()
                guard pattern.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)) != nil else { continue }
                if lower.hasPrefix("com.apple.") || lower.hasPrefix("apple.") || lower.hasPrefix("group.") { continue }
                let parts = lower.split(separator: ".")
                if parts.count >= 2, vendors.contains("\(parts[0]).\(parts[1])") { continue }
                // Ignora identificadores que pertencem (por prefixo) a apps ou componentes instalados.
                let related = installed.contains { lower.hasPrefix($0) || $0.hasPrefix(lower) || sharedVendorPrefix(lower, $0) }
                if !related { urls.append(entry) }
            }
        }
        urls = urls.filter { SafetyGuard.canDelete($0) }
        let sizes = FS.sizes(of: urls)
        return zip(urls, sizes).map {
            CleanItem(url: $0, size: max($1, 1), selected: false, detail: $0.deletingLastPathComponent().displayPath)
        }.sorted { $0.size > $1.size }
    }

    /// Mesmo programador e produto (ex.: com.foo.app e com.foo.app-helper).
    private static func sharedVendorPrefix(_ a: String, _ b: String) -> Bool {
        let pa = a.split(separator: "."), pb = b.split(separator: ".")
        guard pa.count >= 3, pb.count >= 3 else { return false }
        return pa[0] == pb[0] && pa[1] == pb[1] && (pa[2].hasPrefix(pb[2]) || pb[2].hasPrefix(pa[2]))
    }

    /// Todos os bundle IDs de apps no sistema (via Spotlight), para evitar falsos órfãos.
    static func allSystemBundleIDs() async -> Set<String> {
        // O Spotlight já indexa o identificador: não é preciso abrir cada app.
        let r = await Shell.run("/usr/bin/mdfind", ["-attr", "kMDItemCFBundleIdentifier", "kMDItemContentType == 'com.apple.application-bundle'"])
        var ids = Set<String>()
        for line in r.out.split(separator: "\n") {
            guard let range = line.range(of: "kMDItemCFBundleIdentifier = ") else { continue }
            let id = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if !id.isEmpty && id != "(null)" { ids.insert(id) }
        }
        return ids
    }
}

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
