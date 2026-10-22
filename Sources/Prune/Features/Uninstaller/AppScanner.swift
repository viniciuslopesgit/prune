import AppKit

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
                if systemPrefixes.contains(where: lower.hasPrefix) || lower == ownBundleID { continue }
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

    /// Domínios do macOS que não pertencem a nenhuma app (impressão, iCloud, grupos partilhados…).
    private static let systemPrefixes = ["com.apple.", "apple.", "group.", "systemgroup.", "org.cups.", "com.openssh."]
    private static let ownBundleID = Bundle.main.bundleIdentifier?.lowercased() ?? "app.prune.prune"

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
