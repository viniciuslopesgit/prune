import Foundation

/// Privacy: history, cookies, caches and browsing data, recent items.
enum PrivacyScanner {
    struct Chromium {
        let name: String
        let bundleID: String
        let support: String
        let cache: String
    }

    static let chromiumBrowsers: [Chromium] = [
        .init(name: "Google Chrome", bundleID: "com.google.Chrome", support: "Library/Application Support/Google/Chrome", cache: "Library/Caches/Google/Chrome"),
        .init(name: "Microsoft Edge", bundleID: "com.microsoft.edgemac", support: "Library/Application Support/Microsoft Edge", cache: "Library/Caches/Microsoft Edge"),
        .init(name: "Brave", bundleID: "com.brave.Browser", support: "Library/Application Support/BraveSoftware/Brave-Browser", cache: "Library/Caches/BraveSoftware/Brave-Browser"),
        .init(name: "Opera", bundleID: "com.operasoftware.Opera", support: "Library/Application Support/com.operasoftware.Opera", cache: "Library/Caches/com.operasoftware.Opera"),
        .init(name: "Vivaldi", bundleID: "com.vivaldi.Vivaldi", support: "Library/Application Support/Vivaldi", cache: "Library/Caches/Vivaldi"),
        .init(name: "Arc", bundleID: "company.thebrowser.Browser", support: "Library/Application Support/Arc/User Data", cache: "Library/Caches/Arc"),
        .init(name: "Chromium", bundleID: "org.chromium.Chromium", support: "Library/Application Support/Chromium", cache: "Library/Caches/Chromium"),
    ]

    /// Browsers that must be closed to clean their data.
    static var browserBundleIDs: [String: String] {
        var d = ["com.apple.Safari": "Safari", "org.mozilla.firefox": "Firefox"]
        for b in chromiumBrowsers { d[b.bundleID] = b.name }
        return d
    }

    static func scan(_ p: ProgressReporter) async -> [CleanCategory] {
        var cats: [CleanCategory] = []
        p.report(String(localized: "Scanning Safari…"), force: true)
        if let c = safari() { cats.append(c) }
        for b in chromiumBrowsers {
            p.report(String(localized: "Scanning \(b.name)…"))
            if let c = chromium(b) { cats.append(c) }
        }
        p.report(String(localized: "Scanning Firefox…"))
        if let c = firefox() { cats.append(c) }
        p.report(String(localized: "Scanning recent items…"))
        cats.append(recentItems())
        return cats
    }

    private static func files(_ paths: [String], base: URL, detail: String, selected: Bool = true) -> [CleanItem] {
        paths.flatMap { name -> [CleanItem] in
            // Includes SQLite's auxiliary files (-wal, -shm, -journal).
            [name, name + "-wal", name + "-shm", name + "-journal"].compactMap {
                FS.item(base.appendingPathComponent($0), selected: selected, detail: detail)
            }
        }
    }

    static func safari() -> CleanCategory? {
        let safari = URL.home("Library/Safari")
        let container = URL.home("Library/Containers/com.apple.Safari/Data/Library")
        guard safari.exists || container.exists else { return nil }
        var items: [CleanItem] = []
        items += files(["History.db"], base: safari, detail: String(localized: "Browsing history"))
        items += files(["Downloads.plist"], base: safari, detail: String(localized: "Download history"))
        items += files(["RecentlyClosedTabs.plist"], base: safari, detail: String(localized: "Recently closed tabs"))
        items += files(["TopSites.plist"], base: safari, detail: String(localized: "Top sites"), selected: false)
        if let i = FS.item(container.appendingPathComponent("Cookies"), name: "Cookies", detail: String(localized: "Signs you out of websites")) { items.append(i) }
        if let i = FS.item(container.appendingPathComponent("Caches/com.apple.Safari"), name: String(localized: "Safari cache"), detail: String(localized: "Web page cache")) { items.append(i) }
        if let i = FS.item(safari.appendingPathComponent("LocalStorage"), selected: false, name: String(localized: "Local storage"), detail: String(localized: "Data saved by websites")) { items.append(i) }
        if let i = FS.item(container.appendingPathComponent("WebKit/WebsiteData"), selected: false, name: String(localized: "Website data"), detail: "IndexedDB, Service Workers…") { items.append(i) }
        guard !items.isEmpty || !Permissions.hasFullDiskAccess else {
            return nil
        }
        return CleanCategory(
            id: "safari", name: "Safari", icon: "safari",
            info: String(localized: "History, cookies and cache. Quit Safari to clean."),
            items: items,
            warning: Permissions.hasFullDiskAccess ? nil : String(localized: "Grant Full Disk Access to see all of Safari's data.")
        )
    }

    static func chromium(_ b: Chromium) -> CleanCategory? {
        let base = URL.home(b.support)
        guard base.exists else { return nil }
        // A profile that is a link would offer the files of the folder it points to.
        let profiles = FS.children(base).filter {
            let n = $0.lastPathComponent
            return (n == "Default" || n.hasPrefix("Profile ") || n == "Guest Profile") && !FS.isLink($0)
        }
        var items: [CleanItem] = []
        for profile in profiles {
            let tag = profiles.count > 1 ? " (\(profile.lastPathComponent))" : ""
            items += files(["History"], base: profile, detail: String(localized: "Browsing and download history\(tag)"))
            items += files(["Visited Links"], base: profile, detail: String(localized: "Visited links\(tag)"))
            items += files(["Top Sites"], base: profile, detail: String(localized: "Top sites\(tag)"))
            items += files(["Shortcuts"], base: profile, detail: String(localized: "Address bar suggestions\(tag)"))
            items += files(["Cookies", "Network/Cookies"], base: profile, detail: String(localized: "Cookies. Signs you out of websites\(tag)"))
            items += files(["Web Data"], base: profile, detail: String(localized: "Autofill, without passwords\(tag)"), selected: false)
            for cache in ["Cache", "Code Cache", "GPUCache", "Service Worker/CacheStorage"] {
                if let i = FS.item(profile.appendingPathComponent(cache), name: cache, detail: "Cache" + tag) { items.append(i) }
            }
        }
        if let i = FS.item(URL.home(b.cache), name: String(localized: "Disk cache"), detail: URL.home(b.cache).displayPath) { items.append(i) }
        guard !items.isEmpty else { return nil }
        return CleanCategory(
            id: b.bundleID, name: b.name, icon: "globe",
            info: String(localized: "History, cookies and caches. Passwords and bookmarks stay intact. Quit \(b.name) to clean."),
            items: items
        )
    }

    static func firefox() -> CleanCategory? {
        let base = URL.home("Library/Application Support/Firefox/Profiles")
        guard base.exists else { return nil }
        var items: [CleanItem] = []
        for profile in FS.children(base) where profile.isDirectory && !FS.isLink(profile) {
            let tag = " (\(profile.lastPathComponent))"
            let places = profile.appendingPathComponent("places.sqlite")
            // The SQL below changes the file in place: through a link it would change another database.
            if places.exists && !FS.isLink(places) {
                let path = places.path
                // Deletes the history but keeps the bookmarks (which live in the same file).
                items.append(CleanItem(
                    url: places, name: String(localized: "Browsing history"), size: FS.size(of: places) / 2,
                    detail: String(localized: "Keeps bookmarks\(tag)"),
                    customAction: {
                        let sql = "DELETE FROM moz_historyvisits; DELETE FROM moz_inputhistory; DELETE FROM moz_places WHERE id NOT IN (SELECT fk FROM moz_bookmarks WHERE fk IS NOT NULL) AND id NOT IN (SELECT place_id FROM moz_annos); VACUUM;"
                        return await Shell.run("/usr/bin/sqlite3", [path, sql]).ok
                    }
                ))
            }
            items += files(["cookies.sqlite"], base: profile, detail: "Cookies" + tag)
            items += files(["formhistory.sqlite"], base: profile, detail: String(localized: "Form history\(tag)"))
            items += files(["sessionstore.jsonlz4"], base: profile, detail: String(localized: "Saved session\(tag)"), selected: false)
            if let i = FS.item(profile.appendingPathComponent("sessionstore-backups"), selected: false, name: String(localized: "Session backups"), detail: tag) { items.append(i) }
        }
        let caches = URL.home("Library/Caches/Firefox/Profiles")
        if let i = FS.item(caches, name: String(localized: "Disk cache")) { items.append(i) }
        guard !items.isEmpty else { return nil }
        return CleanCategory(
            id: "org.mozilla.firefox", name: "Firefox", icon: "flame",
            info: String(localized: "History, cookies and cache. Passwords and bookmarks stay intact. Quit Firefox to clean."),
            items: items
        )
    }

    static func recentItems() -> CleanCategory {
        var items: [CleanItem] = []
        let sfl = URL.home("Library/Application Support/com.apple.sharedfilelist")
        let labels: [String: String] = [
            "com.apple.LSSharedFileList.RecentDocuments": String(localized: "Recent documents"),
            "com.apple.LSSharedFileList.RecentApplications": String(localized: "Recent applications"),
            "com.apple.LSSharedFileList.RecentServers": String(localized: "Recent servers"),
            "com.apple.LSSharedFileList.RecentHosts": String(localized: "Recent computers"),
        ]
        for file in FS.children(sfl) {
            let key = file.deletingPathExtension().lastPathComponent
            if let label = labels[key], let i = FS.item(file, name: label, detail: String(localized: "Apple menu ▸ Recent Items list")) { items.append(i) }
        }
        let perApp = sfl.appendingPathComponent("com.apple.LSSharedFileList.ApplicationRecentDocuments")
        if let i = FS.item(perApp, name: String(localized: "Recent documents per app"), detail: String(localized: "Each app's \"Open Recent\" list")) { items.append(i) }
        items.append(CleanItem(
            url: URL.home("Library/Preferences/com.apple.finder.plist"), name: String(localized: "Finder recent folders"), size: 4096,
            detail: String(localized: "Go ▸ Recent Folders menu"),
            customAction: { await Shell.run("/usr/bin/defaults", ["delete", "com.apple.finder", "FXRecentFolders"]).ok || true }
        ))
        items.append(CleanItem(
            url: URL.home("Library/Caches/com.apple.QuickLook.thumbnailcache"), name: String(localized: "Quick Look thumbnails"), size: 4096,
            detail: String(localized: "Cached previews"),
            customAction: { await Shell.run("/usr/bin/qlmanage", ["-r", "cache"]).ok }
        ))
        return CleanCategory(
            id: "recent", name: String(localized: "Recent items"), icon: "clock",
            info: String(localized: "Recently used documents, apps and servers."),
            items: items
        )
    }
}
