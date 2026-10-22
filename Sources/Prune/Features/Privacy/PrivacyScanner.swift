import Foundation

/// Privacidade: histórico, cookies, caches e dados de navegação, itens recentes.
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

    /// Navegadores que têm de estar fechados para limpar os dados.
    static var browserBundleIDs: [String: String] {
        var d = ["com.apple.Safari": "Safari", "org.mozilla.firefox": "Firefox"]
        for b in chromiumBrowsers { d[b.bundleID] = b.name }
        return d
    }

    static func scan(_ p: ProgressReporter) async -> [CleanCategory] {
        var cats: [CleanCategory] = []
        p.report("A analisar Safari…", force: true)
        if let c = safari() { cats.append(c) }
        for b in chromiumBrowsers {
            p.report("A analisar \(b.name)…")
            if let c = chromium(b) { cats.append(c) }
        }
        p.report("A analisar Firefox…")
        if let c = firefox() { cats.append(c) }
        p.report("A analisar itens recentes…")
        cats.append(recentItems())
        return cats
    }

    private static func files(_ paths: [String], base: URL, detail: String, selected: Bool = true) -> [CleanItem] {
        paths.flatMap { name -> [CleanItem] in
            // Inclui ficheiros auxiliares do SQLite (-wal, -shm, -journal).
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
        items += files(["History.db"], base: safari, detail: "Histórico de navegação")
        items += files(["Downloads.plist"], base: safari, detail: "Histórico de transferências")
        items += files(["RecentlyClosedTabs.plist"], base: safari, detail: "Separadores fechados recentemente")
        items += files(["TopSites.plist"], base: safari, detail: "Sites mais visitados", selected: false)
        if let i = FS.item(container.appendingPathComponent("Cookies"), name: "Cookies", detail: "Termina as sessões iniciadas") { items.append(i) }
        if let i = FS.item(container.appendingPathComponent("Caches/com.apple.Safari"), name: "Cache do Safari", detail: "Cache de páginas web") { items.append(i) }
        if let i = FS.item(safari.appendingPathComponent("LocalStorage"), selected: false, name: "Armazenamento local", detail: "Dados guardados por sites") { items.append(i) }
        if let i = FS.item(container.appendingPathComponent("WebKit/WebsiteData"), selected: false, name: "Dados de sites", detail: "IndexedDB, Service Workers…") { items.append(i) }
        guard !items.isEmpty || !Permissions.hasFullDiskAccess else {
            return nil
        }
        return CleanCategory(
            id: "safari", name: "Safari", icon: "safari",
            info: "Histórico, cookies e cache. Feche o Safari para limpar.",
            items: items,
            warning: Permissions.hasFullDiskAccess ? nil : "Dê Acesso Total ao Disco para ver todos os dados do Safari."
        )
    }

    static func chromium(_ b: Chromium) -> CleanCategory? {
        let base = URL.home(b.support)
        guard base.exists else { return nil }
        let profiles = FS.children(base).filter {
            let n = $0.lastPathComponent
            return n == "Default" || n.hasPrefix("Profile ") || n == "Guest Profile"
        }
        var items: [CleanItem] = []
        for profile in profiles {
            let tag = profiles.count > 1 ? " (\(profile.lastPathComponent))" : ""
            items += files(["History"], base: profile, detail: "Histórico de navegação e transferências\(tag)")
            items += files(["Visited Links"], base: profile, detail: "Ligações visitadas\(tag)")
            items += files(["Top Sites"], base: profile, detail: "Sites mais visitados\(tag)")
            items += files(["Shortcuts"], base: profile, detail: "Sugestões da barra de endereço\(tag)")
            items += files(["Cookies", "Network/Cookies"], base: profile, detail: "Cookies. Termina as sessões iniciadas\(tag)")
            items += files(["Web Data"], base: profile, detail: "Preenchimento automático, sem palavras-passe\(tag)", selected: false)
            for cache in ["Cache", "Code Cache", "GPUCache", "Service Worker/CacheStorage"] {
                if let i = FS.item(profile.appendingPathComponent(cache), name: cache, detail: "Cache\(tag)") { items.append(i) }
            }
        }
        if let i = FS.item(URL.home(b.cache), name: "Cache de disco", detail: URL.home(b.cache).displayPath) { items.append(i) }
        guard !items.isEmpty else { return nil }
        return CleanCategory(
            id: b.bundleID, name: b.name, icon: "globe",
            info: "Histórico, cookies e caches. Palavras-passe e marcadores ficam intactos. Feche o \(b.name) para limpar.",
            items: items
        )
    }

    static func firefox() -> CleanCategory? {
        let base = URL.home("Library/Application Support/Firefox/Profiles")
        guard base.exists else { return nil }
        var items: [CleanItem] = []
        for profile in FS.children(base) where profile.isDirectory {
            let tag = " (\(profile.lastPathComponent))"
            let places = profile.appendingPathComponent("places.sqlite")
            if places.exists {
                let path = places.path
                // Apaga o histórico mas mantém os marcadores (que vivem no mesmo ficheiro).
                items.append(CleanItem(
                    url: places, name: "Histórico de navegação", size: FS.size(of: places) / 2,
                    detail: "Mantém os marcadores\(tag)",
                    customAction: {
                        let sql = "DELETE FROM moz_historyvisits; DELETE FROM moz_inputhistory; DELETE FROM moz_places WHERE id NOT IN (SELECT fk FROM moz_bookmarks WHERE fk IS NOT NULL) AND id NOT IN (SELECT place_id FROM moz_annos); VACUUM;"
                        return await Shell.run("/usr/bin/sqlite3", [path, sql]).ok
                    }
                ))
            }
            items += files(["cookies.sqlite"], base: profile, detail: "Cookies\(tag)")
            items += files(["formhistory.sqlite"], base: profile, detail: "Histórico de formulários\(tag)")
            items += files(["sessionstore.jsonlz4"], base: profile, detail: "Sessão guardada\(tag)", selected: false)
            if let i = FS.item(profile.appendingPathComponent("sessionstore-backups"), selected: false, name: "Cópias da sessão", detail: tag) { items.append(i) }
        }
        let caches = URL.home("Library/Caches/Firefox/Profiles")
        if let i = FS.item(caches, name: "Cache de disco") { items.append(i) }
        guard !items.isEmpty else { return nil }
        return CleanCategory(
            id: "org.mozilla.firefox", name: "Firefox", icon: "flame",
            info: "Histórico, cookies e cache. Palavras-passe e marcadores ficam intactos. Feche o Firefox para limpar.",
            items: items
        )
    }

    static func recentItems() -> CleanCategory {
        var items: [CleanItem] = []
        let sfl = URL.home("Library/Application Support/com.apple.sharedfilelist")
        let labels: [String: String] = [
            "com.apple.LSSharedFileList.RecentDocuments": "Documentos recentes",
            "com.apple.LSSharedFileList.RecentApplications": "Aplicações recentes",
            "com.apple.LSSharedFileList.RecentServers": "Servidores recentes",
            "com.apple.LSSharedFileList.RecentHosts": "Computadores recentes",
        ]
        for file in FS.children(sfl) {
            let key = file.deletingPathExtension().lastPathComponent
            if let label = labels[key], let i = FS.item(file, name: label, detail: "Lista do menu Apple ▸ Itens recentes") { items.append(i) }
        }
        let perApp = sfl.appendingPathComponent("com.apple.LSSharedFileList.ApplicationRecentDocuments")
        if let i = FS.item(perApp, name: "Documentos recentes por app", detail: "Lista \"Abrir recentes\" de cada app") { items.append(i) }
        items.append(CleanItem(
            url: URL.home("Library/Preferences/com.apple.finder.plist"), name: "Pastas recentes do Finder", size: 4096,
            detail: "Menu Ir ▸ Pastas recentes",
            customAction: { await Shell.run("/usr/bin/defaults", ["delete", "com.apple.finder", "FXRecentFolders"]).ok || true }
        ))
        items.append(CleanItem(
            url: URL.home("Library/Caches/com.apple.QuickLook.thumbnailcache"), name: "Miniaturas do Quick Look", size: 4096,
            detail: "Pré-visualizações em cache",
            customAction: { await Shell.run("/usr/bin/qlmanage", ["-r", "cache"]).ok }
        ))
        return CleanCategory(
            id: "recent", name: "Itens recentes", icon: "clock",
            info: "Documentos, apps e servidores usados recentemente.",
            items: items
        )
    }
}
