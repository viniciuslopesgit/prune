import AppKit

/// System Junk: caches, logs, temporary files, developer junk, broken preferences…
enum SystemJunkScanner {
    /// Caches that must not be removed while the app/system is using them.
    static let cacheExclusions: Set<String> = [
        "CloudKit", "com.apple.bird", "com.apple.akd", "FamilyCircle", "com.apple.homed",
        "com.apple.containermanagerd", "com.apple.ap.adprivacyd", "com.apple.Safari.SafeBrowsing",
        "com.apple.nsservicescache", "com.apple.iCloudHelper", "Prune", "app.prune.Prune", "com.apple.amsengagementd",
        "com.apple.ctcategories", "GeoServices",
    ]

    static func scan(_ p: ProgressReporter) async -> [CleanCategory] {
        let lib = URL.home("Library")
        var cats: [CleanCategory] = []

        p.report(String(localized: "Scanning user caches…"), force: true)
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        cats.append(userCaches(running: running))

        p.report(String(localized: "Scanning system caches…"))
        cats.append(CleanCategory(
            id: "systemCache", name: String(localized: "System caches"), icon: "gearshape.2",
            info: String(localized: "Shared by all accounts. Some ask for the administrator password."),
            items: FS.childItems(of: URL(fileURLWithPath: "/Library/Caches"), excluding: ["com.apple.iconservices", "com.apple.amsd"])
        ))

        p.report(String(localized: "Scanning logs…"))
        cats.append(CleanCategory(
            id: "userLogs", name: String(localized: "User logs"), icon: "doc.text",
            info: String(localized: "Activity logs from apps. Only useful for diagnostics."),
            items: FS.childItems(of: lib.appendingPathComponent("Logs"), excluding: ["DiagnosticReports"])
        ))
        cats.append(CleanCategory(
            id: "systemLogs", name: String(localized: "System logs"), icon: "doc.text.fill",
            info: String(localized: "Logs from system services and installers."),
            items: FS.childItems(of: URL(fileURLWithPath: "/Library/Logs"), excluding: ["DiagnosticReports"])
        ))

        p.report(String(localized: "Scanning crash reports…"))
        cats.append(CleanCategory(
            id: "crash", name: String(localized: "Crash reports"), icon: "exclamationmark.triangle",
            info: String(localized: "Created when an app crashes or hangs."),
            items: FS.childItems(of: lib.appendingPathComponent("Logs/DiagnosticReports"))
                + FS.childItems(of: URL(fileURLWithPath: "/Library/Logs/DiagnosticReports"))
        ))

        p.report(String(localized: "Scanning temporary files…"))
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let twoDaysAgo = Date().addingTimeInterval(-2 * 86400)
        cats.append(CleanCategory(
            id: "temp", name: String(localized: "Temporary files"), icon: "clock.arrow.circlepath",
            info: String(localized: "Temporary files older than 2 days."),
            items: FS.childItems(of: tmp, excluding: ["Prune", "app.prune.Prune", "com.apple"], olderThan: twoDaysAgo)
        ))

        p.report(String(localized: "Scanning Xcode junk…"))
        cats.append(xcodeJunk())

        p.report(String(localized: "Scanning developer caches…"))
        cats.append(devCaches())

        p.report(String(localized: "Scanning iPhone and iPad files…"))
        cats.append(iosFiles())

        p.report(String(localized: "Looking for broken preferences…"))
        cats.append(brokenPreferences())

        p.report(String(localized: "Looking for broken login items…"))
        cats.append(brokenLaunchAgents())

        p.report(String(localized: "Scanning download caches…"))
        cats.append(downloadsJunk())

        return cats
    }

    /// ~/Library/Caches without the caches in use by the system or covered by another category.
    /// Caches of open apps are not selected (they may be in use).
    static func userCaches(running: Set<String>) -> CleanCategory {
        var items = FS.childItems(of: URL.home("Library/Caches"), excluding: cacheExclusions.union(["Homebrew", "pip", "Yarn", "CocoaPods", "node-gyp", "ms-playwright", "com.apple.dt.Xcode"]))
        let open = Set(running.map { $0.lowercased() })
        for j in items.indices where open.contains(items[j].name.lowercased()) {
            items[j].selected = false
            items[j].detail = String(localized: "App is open. Quit it to clean.")
        }
        return CleanCategory(
            id: "userCache", name: String(localized: "User caches"), icon: "shippingbox",
            info: String(localized: "Temporary files from apps. They are recreated when needed."),
            items: items
        )
    }

    static func xcodeJunk() -> CleanCategory {
        let dev = URL.home("Library/Developer")
        var items: [CleanItem] = []
        if let i = FS.item(dev.appendingPathComponent("Xcode/DerivedData"), name: "DerivedData", detail: String(localized: "Intermediate build files")) { items.append(i) }
        if let i = FS.item(URL.home("Library/Caches/com.apple.dt.Xcode"), name: String(localized: "Xcode cache")) { items.append(i) }
        for sub in ["iOS DeviceSupport", "watchOS DeviceSupport", "tvOS DeviceSupport", "visionOS DeviceSupport"] {
            items += FS.childItems(of: dev.appendingPathComponent("Xcode/\(sub)"), detail: String(localized: "\(sub.replacingOccurrences(of: " DeviceSupport", with: "")) symbols"))
        }
        if let i = FS.item(dev.appendingPathComponent("CoreSimulator/Caches"), name: String(localized: "Simulator caches")) { items.append(i) }
        if let i = FS.item(dev.appendingPathComponent("Xcode/UserData/Previews"), name: String(localized: "SwiftUI previews")) { items.append(i) }
        items += FS.childItems(of: dev.appendingPathComponent("Xcode/Archives"), selected: false, detail: String(localized: "Build archive. Check before removing."))
        return CleanCategory(
            id: "xcode", name: String(localized: "Xcode junk"), icon: "hammer",
            info: String(localized: "Build data, device symbols and simulator caches. Archives are not selected."),
            items: items
        )
    }

    static func devCaches() -> CleanCategory {
        let candidates: [(String, String)] = [
            (".npm/_cacache", "npm"), ("Library/Caches/Yarn", "Yarn"), (".yarn/berry/cache", "Yarn Berry"),
            ("Library/pnpm/store", "pnpm"), ("Library/Caches/pip", "pip"), (".cache/pip", "pip"),
            ("Library/Caches/Homebrew", "Homebrew"), ("Library/Caches/CocoaPods", "CocoaPods"),
            (".gradle/caches", "Gradle"), (".m2/repository", "Maven"), (".cargo/registry/cache", "Cargo"),
            ("go/pkg/mod/cache", "Go"), (".cache/huggingface", "Hugging Face"), ("Library/Caches/node-gyp", "node-gyp"),
            ("Library/Caches/ms-playwright", "Playwright"), (".bun/install/cache", "Bun"), (".cache/uv", "uv"),
            ("Library/Caches/org.swift.swiftpm", "Swift PM"), (".composer/cache", "Composer"), (".nuget/packages", "NuGet"),
            ("Library/Android/sdk/.temp", "Android SDK"), (".android/cache", "Android"),
        ]
        var seen = Set<String>()
        let items = candidates.compactMap { (path, name) -> CleanItem? in
            let url = URL.home(path)
            guard !seen.contains(url.path) else { return nil }
            seen.insert(url.path)
            let selected = !["Maven", "NuGet", "Hugging Face"].contains(name)
            return FS.item(url, selected: selected, name: name, detail: url.displayPath)
        }
        return CleanCategory(
            id: "dev", name: String(localized: "Developer caches"), icon: "chevron.left.forwardslash.chevron.right",
            info: String(localized: "Packages from npm, pip, Homebrew, Gradle and others. They are downloaded again when needed."),
            items: items
        )
    }

    static func iosFiles() -> CleanCategory {
        var items: [CleanItem] = []
        for sub in ["iPhone Software Updates", "iPad Software Updates", "iPod Software Updates"] {
            items += FS.childItems(of: URL.home("Library/iTunes/\(sub)"), detail: String(localized: "Update file (IPSW)"))
        }
        let backups = FS.childItems(of: URL.home("Library/Application Support/MobileSync/Backup"), selected: false, detail: String(localized: "Device backup"))
        items += backups.map { item in
            var i = item
            let info = item.url.appendingPathComponent("Info.plist")
            if let dict = NSDictionary(contentsOf: info), let name = dict["Device Name"] as? String {
                let date = (dict["Last Backup Date"] as? Date).map { " — " + Fmt.date($0) } ?? ""
                i.name = String(localized: "Backup: \(name)\(date)")
            }
            return i
        }
        return CleanCategory(
            id: "ios", name: String(localized: "iPhone and iPad"), icon: "iphone",
            info: String(localized: "Firmware updates and backups. Backups are never selected."),
            items: items,
            warning: backups.isEmpty ? nil : String(localized: "A removed backup cannot be recovered.")
        )
    }

    static func brokenPreferences() -> CleanCategory {
        let prefs = URL.home("Library/Preferences")
        var items: [CleanItem] = []
        let files = FS.children(prefs) + FS.children(prefs.appendingPathComponent("ByHost"))
        for url in files where url.pathExtension == "plist" {
            guard let data = try? Data(contentsOf: url) else { continue }
            if data.isEmpty || (try? PropertyListSerialization.propertyList(from: data, format: nil)) == nil {
                items.append(CleanItem(url: url, size: max(Int64(data.count), 4096), detail: String(localized: "Unreadable file")))
            }
        }
        return CleanCategory(
            id: "brokenPrefs", name: String(localized: "Broken preferences"), icon: "wrench.and.screwdriver",
            info: String(localized: "Corrupted .plist files that can cause errors in apps."),
            items: items
        )
    }

    static func brokenLaunchAgents() -> CleanCategory {
        let dir = URL.home("Library/LaunchAgents")
        var items: [CleanItem] = []
        for url in FS.children(dir) where url.pathExtension == "plist" {
            guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
                items.append(CleanItem(url: url, size: 4096, detail: String(localized: "Unreadable file")))
                continue
            }
            if let program = LaunchItemParser.program(of: dict), !program.hasPrefix("/usr/bin"), !program.hasPrefix("/bin"),
               program.hasPrefix("/"), !FileManager.default.fileExists(atPath: program) {
                items.append(CleanItem(url: url, size: 4096, detail: String(localized: "The program no longer exists: \(program)")))
            }
        }
        return CleanCategory(
            id: "brokenAgents", name: String(localized: "Broken login items"), icon: "bolt.slash",
            info: String(localized: "Launch agents of programs that no longer exist."),
            items: items
        )
    }

    static func downloadsJunk() -> CleanCategory {
        let downloads = URL.home("Downloads")
        let items = FS.children(downloads).filter {
            ["download", "crdownload", "part", "partial", "opdownload"].contains($0.pathExtension.lowercased())
        }.compactMap { FS.item($0, detail: String(localized: "Incomplete download")) }
        return CleanCategory(
            id: "partialDownloads", name: String(localized: "Incomplete downloads"), icon: "arrow.down.circle.dotted",
            info: String(localized: "Interrupted or failed downloads."),
            items: items
        )
    }
}
