import AppKit
import Foundation
import Observation

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
    case safari = "Safari"
    case browsers = "Outros navegadores"
    case share = "Partilha"
    case finder = "Finder"
    case widgets = "Widgets"
    case quicklook = "Quick Look"
    case spotlight = "Spotlight"
    case prefPanes = "Painéis de preferências"
    case plugins = "Plug-ins da Internet"
    case other = "Outras"
    var id: String { rawValue }

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
            ("/Library/PreferencePanes", .prefPanes, "Painel de preferências"),
            ("~/Library/PreferencePanes", .prefPanes, "Painel de preferências"),
            ("/Library/Internet Plug-Ins", .plugins, "Plug-in"),
            ("~/Library/Internet Plug-Ins", .plugins, "Plug-in"),
            ("/Library/Spotlight", .spotlight, "Importador do Spotlight"),
            ("~/Library/Spotlight", .spotlight, "Importador do Spotlight"),
            ("/Library/QuickLook", .quicklook, "Gerador Quick Look"),
            ("~/Library/QuickLook", .quicklook, "Gerador Quick Look"),
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
            for profile in FS.children(base) where profile.lastPathComponent == "Default" || profile.lastPathComponent.hasPrefix("Profile ") {
                let prefs = (try? Data(contentsOf: profile.appendingPathComponent("Preferences")))
                    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                let settings = ((prefs?["extensions"] as? [String: Any])?["settings"] as? [String: Any]) ?? [:]
                for extDir in FS.children(profile.appendingPathComponent("Extensions")) where extDir.isDirectory {
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
        for profile in FS.children(ffBase) {
            guard let data = try? Data(contentsOf: profile.appendingPathComponent("extensions.json")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let addons = json["addons"] as? [[String: Any]] else { continue }
            for a in addons where (a["type"] as? String) == "extension" && (a["location"] as? String) == "app-profile" {
                guard let path = a["path"] as? String else { continue }
                let name = ((a["defaultLocale"] as? [String: Any])?["name"] as? String) ?? (a["id"] as? String ?? "?")
                let perms = ((a["userPermissions"] as? [String: Any])?["origins"] as? [String]) ?? []
                result.append(BrowserExtension(
                    url: URL(fileURLWithPath: path), name: name, identifier: a["id"] as? String ?? "",
                    browser: "Firefox", version: a["version"] as? String ?? "", permissions: perms, fromStore: a["signedState"] as? Int == 2
                ))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func localized(_ name: String, dir: URL, manifest: [String: Any]) -> String {
        guard name.hasPrefix("__MSG_"), name.hasSuffix("__") else { return name }
        let key = String(name.dropFirst(6).dropLast(2)).lowercased()
        let locales = [manifest["default_locale"] as? String, "pt_PT", "pt_BR", "pt", "en", "en_US"].compactMap { $0 }
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

@MainActor
@Observable
final class ExtensionsModel {
    var category: ExtensionCategory = .safari
    var system: [SystemExtension] = []
    var browser: [BrowserExtension] = []
    var files: [ExtensionCategory: [PluginFile]] = [:]
    var showSystem = false
    var loading = false
    var loaded = false
    var message: String?

    func load() async {
        loading = true
        async let s = ExtensionService.systemExtensions()
        let b = await Task.detached { BrowserExtensions.scanAll() }.value
        let f = await Task.detached { ExtensionService.pluginFiles() }.value
        system = await s
        browser = b
        files = f
        loading = false
        loaded = true
    }

    func extensions(in cat: ExtensionCategory) -> [SystemExtension] {
        system.filter { ExtensionCategory.from(sdk: $0.sdk) == cat && (showSystem || !$0.isSystem) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func count(_ cat: ExtensionCategory) -> Int {
        switch cat {
        case .browsers: browser.count
        case .prefPanes, .plugins: files[cat]?.count ?? 0
        default: extensions(in: cat).count + (files[cat]?.count ?? 0)
        }
    }

    func toggle(_ ext: SystemExtension) async {
        let ok = await ExtensionService.setEnabled(ext, !ext.enabled)
        if ok, let i = system.firstIndex(where: { $0.id == ext.id }) { system[i].enabled.toggle() }
        if !ok { message = "Não foi possível alterar \(ext.name)." }
    }

    func remove(_ ext: BrowserExtension) async {
        let bundleIDs = PrivacyScanner.browserBundleIDs.filter { ext.browser.hasPrefix($0.value) }.map(\.key)
        if bundleIDs.contains(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) {
            message = "Feche o \(ext.browser) antes de remover a extensão."
            return
        }
        let r = await Cleaner.remove(urls: [ext.url], mode: .trash)
        if r.failed.isEmpty { browser.removeAll { $0.id == ext.id } } else { message = "Não foi possível remover \(ext.name)." }
    }

    func remove(_ file: PluginFile, category: ExtensionCategory) async {
        var r = await Cleaner.remove(urls: [file.url], mode: .trash)
        if !r.failed.isEmpty { r = await Cleaner.retryAsAdmin([file.url], mode: .trash) }
        if r.failed.isEmpty { files[category]?.removeAll { $0.id == file.id } } else { message = "Não foi possível remover \(file.url.lastPathComponent)." }
    }
}
