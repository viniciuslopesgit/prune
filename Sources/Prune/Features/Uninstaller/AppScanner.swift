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

    /// Lists the apps installed by the user (excludes Apple's system apps).
    static func installedApps(includeApple: Bool = false, computeSizes: Bool = true) -> [AppInfo] {
        var urls: [URL] = []
        for folder in appFolders {
            for child in FS.children(folder) {
                if child.pathExtension == "app" {
                    urls.append(child)
                } else if child.isDirectory, !child.isPackage, folder.lastPathComponent == "Applications" {
                    // Apps inside subfolders (e.g. /Applications/Adobe Photoshop/…)
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
            // Each app's Spotlight data and plist are freed before the next one.
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

    /// Last-used dates of every app in a single Spotlight query
    /// (creating an NSMetadataItem per app is slow and leaves ~30 MB of temporary data).
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

    /// Support files the app has spread across the system.
    static func leftovers(for app: AppInfo) -> [CleanItem] {
        let names = Set([app.name, app.url.deletingPathExtension().lastPathComponent]
            .map { $0.lowercased() }
            .flatMap { [$0, $0.replacingOccurrences(of: " ", with: "")] }
            .filter { $0.count >= 4 })
        var found: [URL] = []
        for loc in leftoverLocations {
            for entry in FS.children(expand(loc)) where isLeftover(entry.lastPathComponent, bundleID: app.bundleID, names: names) {
                found.append(entry)
            }
        }
        found = found.filter { SafetyGuard.canDelete($0) }
        let sizes = FS.sizes(of: found)
        return zip(found, sizes).map { url, size in
            CleanItem(url: url, size: max(size, 1), selected: true, detail: url.deletingLastPathComponent().displayPath)
        }.sorted { $0.size > $1.size }
    }

    /// Whether a file or folder name belongs to the app: its bundle ID as whole dot-separated parts
    /// ("com.foo.app.plist", "TEAMID.com.foo.app", "group.com.foo.app.shared") or its name.
    ///
    /// The bundle ID comes from the app's own Info.plist, which anyone can write. Matching it as any
    /// substring let an app with the ID "e" or "com" preselect almost everything in ~/Library for deletion.
    /// So it must look like a real bundle ID (at least two parts) and only matches at part boundaries.
    static func isLeftover(_ entryName: String, bundleID: String, names: Set<String>) -> Bool {
        let n = entryName.lowercased()
        let stem = (n as NSString).deletingPathExtension
        if names.contains(stem) || names.contains(n) { return true }
        let id = bundleID.lowercased()
        guard id.range(of: #"^[a-z0-9_-]+(\.[a-z0-9_-]+)+$"#, options: .regularExpression) != nil else { return false }
        return n == id || n.hasPrefix(id + ".") || n.hasSuffix("." + id) || n.contains("." + id + ".")
    }

    /// Leftovers of apps that have been removed (folders named after a bundle ID with no matching app).
    static func orphans(installedIDs: Set<String>) -> [CleanItem] {
        var locations = ["~/Library/Application Support", "~/Library/Caches", "~/Library/Preferences",
                         "~/Library/Saved Application State", "~/Library/HTTPStorages",
                         "~/Library/WebKit", "~/Library/Logs"]
        // This scan runs on its own when the Uninstaller opens. Reading inside other apps' containers
        // makes macOS ask for authorization, so they are only included with Full Disk Access.
        if Permissions.hasFullDiskAccess { locations.append("~/Library/Containers") }
        let installed = installedIDs.map { $0.lowercased() }
        // Developers with an app installed (e.g. com.adobe) — their files are not treated as orphans.
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
                // Ignores identifiers that belong (by prefix) to installed apps or components.
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

    /// macOS domains that belong to no app (printing, iCloud, shared groups…).
    private static let systemPrefixes = ["com.apple.", "apple.", "group.", "systemgroup.", "org.cups.", "com.openssh."]
    private static let ownBundleID = Bundle.main.bundleIdentifier?.lowercased() ?? "app.prune.prune"

    /// Same developer and product (e.g. com.foo.app and com.foo.app-helper).
    private static func sharedVendorPrefix(_ a: String, _ b: String) -> Bool {
        let pa = a.split(separator: "."), pb = b.split(separator: ".")
        guard pa.count >= 3, pb.count >= 3 else { return false }
        return pa[0] == pb[0] && pa[1] == pb[1] && (pa[2].hasPrefix(pb[2]) || pb[2].hasPrefix(pa[2]))
    }

    /// Every app bundle ID on the system (via Spotlight), to avoid false orphans.
    static func allSystemBundleIDs() async -> Set<String> {
        // Spotlight already indexes the identifier: there is no need to open each app.
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
