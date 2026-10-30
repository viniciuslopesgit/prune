import Foundation

struct SystemExtension: Identifiable {
    var id: String { identifier + path }
    let identifier: String
    let name: String
    let path: String
    let parent: String?
    let sdk: String
    var enabled: Bool
    var isSystem: Bool { path.hasPrefix("/System/") || identifier.hasPrefix("com.apple.") }
}

struct BrowserExtension: Identifiable {
    var id: String { url.path }
    let url: URL
    let name: String
    let identifier: String
    let browser: String
    let version: String
    let permissions: [String]
    let fromStore: Bool
}

struct PluginFile: Identifiable {
    var id: String { url.path }
    let url: URL
    let kind: String
    let size: Int64
}

enum ExtensionCategory: String, CaseIterable, Identifiable {
    case safari, browsers, share, finder, widgets, quicklook, spotlight, prefPanes, plugins, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .safari: "Safari"
        case .browsers: String(localized: "Other browsers")
        case .share: String(localized: "Sharing")
        case .finder: "Finder"
        case .widgets: String(localized: "Widgets")
        case .quicklook: "Quick Look"
        case .spotlight: "Spotlight"
        case .prefPanes: String(localized: "Preference panes")
        case .plugins: String(localized: "Internet plug-ins")
        case .other: String(localized: "Other")
        }
    }

    var icon: String {
        switch self {
        case .safari: "safari"
        case .browsers: "globe"
        case .share: "square.and.arrow.up"
        case .finder: "folder"
        case .widgets: "square.grid.2x2"
        case .quicklook: "eye"
        case .spotlight: "magnifyingglass"
        case .prefPanes: "gearshape"
        case .plugins: "puzzlepiece"
        case .other: "puzzlepiece.extension"
        }
    }

    static func from(sdk: String) -> ExtensionCategory {
        if sdk.hasPrefix("com.apple.Safari") { return .safari }
        if sdk == "com.apple.share-services" { return .share }
        if sdk == "com.apple.FinderSync" || sdk.hasPrefix("com.apple.fileprovider") || sdk == "com.apple.services" { return .finder }
        if sdk.contains("widget") { return .widgets }
        if sdk.hasPrefix("com.apple.quicklook") { return .quicklook }
        if sdk.hasPrefix("com.apple.spotlight") { return .spotlight }
        return .other
    }
}

enum ExtensionService {
    static func systemExtensions() async -> [SystemExtension] {
        let r = await Shell.run("/usr/bin/pluginkit", ["-mAvvv"])
        var result: [SystemExtension] = []
        var cur: [String: String] = [:]
        var header: (flag: Character?, id: String)?

        func flush() {
            guard let h = header else { return }
            let name = cur["Display Name"] ?? cur["Short Name"] ?? h.id
            result.append(SystemExtension(
                identifier: h.id, name: name, path: cur["Path"] ?? "", parent: cur["Parent Name"],
                sdk: cur["SDK"] ?? "", enabled: h.flag != "-"
            ))
        }

        for raw in r.out.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if let eq = line.range(of: " = "), line.hasPrefix("\t") {
                let key = line[..<eq.lowerBound].trimmingCharacters(in: .whitespaces)
                cur[key] = String(line[eq.upperBound...])
            } else {
                flush()
                cur = [:]
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                var flag: Character?
                var body = Substring(trimmed)
                if let f = body.first, "+-=!".contains(f) {
                    flag = f
                    body = body.dropFirst().drop(while: { $0 == " " })
                }
                let id = body.split(separator: "(").first.map(String.init) ?? String(body)
                header = (flag, id)
            }
        }
        flush()
        return result
    }

    static func setEnabled(_ ext: SystemExtension, _ enabled: Bool) async -> Bool {
        await Shell.run("/usr/bin/pluginkit", ["-e", enabled ? "use" : "ignore", "-i", ext.identifier]).ok
    }

    static func pluginFiles() -> [ExtensionCategory: [PluginFile]] {
        let dirs: [(String, ExtensionCategory, String)] = [
            ("/Library/PreferencePanes", .prefPanes, String(localized: "Preference pane")),
            ("~/Library/PreferencePanes", .prefPanes, String(localized: "Preference pane")),
            ("/Library/Internet Plug-Ins", .plugins, "Plug-in"),
            ("~/Library/Internet Plug-Ins", .plugins, "Plug-in"),
            ("/Library/Spotlight", .spotlight, String(localized: "Spotlight importer")),
            ("~/Library/Spotlight", .spotlight, String(localized: "Spotlight importer")),
            ("/Library/QuickLook", .quicklook, String(localized: "Quick Look generator")),
            ("~/Library/QuickLook", .quicklook, String(localized: "Quick Look generator")),
        ]
        var result: [ExtensionCategory: [PluginFile]] = [:]
        for (path, cat, kind) in dirs {
            for url in FS.children(AppScanner.expand(path)) where !url.lastPathComponent.hasPrefix(".") {
                result[cat, default: []].append(PluginFile(url: url, kind: kind, size: FS.size(of: url)))
            }
        }
        return result
    }
}

enum BrowserExtensions {
    static func scanAll() -> [BrowserExtension] {
        var result: [BrowserExtension] = []
        for b in PrivacyScanner.chromiumBrowsers {
            let base = URL.home(b.support)
            // A profile or an extension folder that is a link would offer the folder it points to for removal.
            for profile in FS.children(base) where (profile.lastPathComponent == "Default" || profile.lastPathComponent.hasPrefix("Profile ")) && !FS.isLink(profile) {
                let prefs = (try? Data(contentsOf: profile.appendingPathComponent("Preferences")))
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let settings = ((prefs?["extensions"] as? [String: Any])?["settings"] as? [String: Any]) ?? [:]
                for extDir in FS.children(profile.appendingPathComponent("Extensions")) where extDir.isDirectory && !FS.isLink(extDir) {
                    guard let versionDir = FS.children(extDir).filter(\.isDirectory).sorted(by: { $0.path > $1.path }).first,
                          let data = try? Data(contentsOf: versionDir.appendingPathComponent("manifest.json")),
                          let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    let id = extDir.lastPathComponent
                    let name = localized(manifest["name"] as? String ?? id, dir: versionDir, manifest: manifest)
                    var perms = (manifest["permissions"] as? [Any] ?? []).compactMap { $0 as? String }
                    perms += (manifest["host_permissions"] as? [String]) ?? []
                    let fromStore = ((settings[id] as? [String: Any])?["from_webstore"] as? Bool) ?? true
                    let tag = profile.lastPathComponent == "Default" ? "" : " · \(profile.lastPathComponent)"
                    result.append(BrowserExtension(
                        url: extDir, name: name, identifier: id, browser: b.name + tag,
                        version: manifest["version"] as? String ?? "", permissions: perms, fromStore: fromStore
                    ))
                }
            }
        }
        // Firefox
        let ffBase = URL.home("Library/Application Support/Firefox/Profiles")
        for profile in FS.children(ffBase) where !FS.isLink(profile) {
            guard let data = try? Data(contentsOf: profile.appendingPathComponent("extensions.json")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let addons = json["addons"] as? [[String: Any]] else { continue }
            for a in addons where (a["type"] as? String) == "extension" && (a["location"] as? String) == "app-profile" {
                guard let path = a["path"] as? String, let url = firefoxExtensionURL(path, profile: profile) else { continue }
                let name = ((a["defaultLocale"] as? [String: Any])?["name"] as? String) ?? (a["id"] as? String ?? "?")
                let perms = ((a["userPermissions"] as? [String: Any])?["origins"] as? [String]) ?? []
                result.append(BrowserExtension(
                    url: url, name: name, identifier: a["id"] as? String ?? "",
                    browser: "Firefox", version: a["version"] as? String ?? "", permissions: perms, fromStore: a["signedState"] as? Int == 2
                ))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The path in extensions.json comes from a file anyone can write in the profile, and removing the
    /// extension sends it to the Trash. So it is only accepted as a direct child of that profile's own
    /// `extensions` folder (resolved), and never as a link.
    static func firefoxExtensionURL(_ path: String, profile: URL) -> URL? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let folder = profile.appendingPathComponent("extensions").path
        guard path.hasPrefix("/"), !FS.isLink(url), url.exists,
              let parent = SafetyGuard.realPath(url.deletingLastPathComponent().path),
              let expected = SafetyGuard.realPath(folder), parent == expected else { return nil }
        return url
    }

    private static func localized(_ name: String, dir: URL, manifest: [String: Any]) -> String {
        guard name.hasPrefix("__MSG_"), name.hasSuffix("__") else { return name }
        let key = String(name.dropFirst(6).dropLast(2)).lowercased()
        let app = Bundle.main.preferredLocalizations.first?.replacingOccurrences(of: "-", with: "_")
        let locales = [app, manifest["default_locale"] as? String, "en", "en_US"].compactMap { $0 }
        for loc in locales {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("_locales/\(loc)/messages.json")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for (k, v) in json where k.lowercased() == key {
                if let msg = (v as? [String: Any])?["message"] as? String { return msg }
            }
        }
        return name
    }
}
