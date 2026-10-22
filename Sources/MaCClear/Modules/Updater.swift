import AppKit
import Foundation
import Observation

struct AppUpdate: Identifiable {
    enum Source: String { case sparkle = "Site do programador", homebrew = "Homebrew", homebrewFormula = "Homebrew (CLI)" }
    var id: String { source.rawValue + name }
    let name: String
    let current: String
    let latest: String
    let source: Source
    var appURL: URL?
    var downloadURL: URL?
    var notesURL: URL?
    var brewName: String?
    var selected = true
}

/// Lê appcasts Sparkle (usados pela maioria das apps fora da App Store).
final class AppcastParser: NSObject, XMLParserDelegate {
    struct Item { var short: String?; var build: String?; var url: String?; var notes: String?; var channel: String?; var minOS: String? }
    private var items: [Item] = []
    private var current: Item?
    private var text = ""

    static func parse(_ data: Data) -> [Item] {
        let p = AppcastParser()
        let parser = XMLParser(data: data)
        parser.delegate = p
        parser.parse()
        return p.items
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if name == "item" { current = Item() }
        if name == "enclosure", current != nil {
            current?.url = attributes["url"] ?? current?.url
            current?.short = attributes["sparkle:shortVersionString"] ?? current?.short
            current?.build = attributes["sparkle:version"] ?? current?.build
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "sparkle:shortVersionString": current?.short = t
        case "sparkle:version": current?.build = t
        case "sparkle:releaseNotesLink": current?.notes = t
        case "sparkle:channel": current?.channel = t
        case "sparkle:minimumSystemVersion": current?.minOS = t
        case "item":
            if let c = current { items.append(c) }
            current = nil
        default: break
        }
    }
}

enum Version {
    /// Compara versões numericamente ("1.10.2" > "1.9").
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = numbers(a), pb = numbers(b)
        guard !pa.isEmpty, !pb.isEmpty else { return false }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    static func numbers(_ s: String) -> [Int] {
        s.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }
}

enum UpdateService {
    static let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

    static func sparkleUpdates(_ apps: [AppInfo], progress: ProgressReporter) async -> [AppUpdate] {
        await withTaskGroup(of: AppUpdate?.self) { group in
            for app in apps {
                guard let feed = app.feedURL, let url = URL(string: feed), url.scheme?.hasPrefix("http") == true else { continue }
                group.addTask {
                    progress.report("A verificar \(app.name)…")
                    var req = URLRequest(url: url, timeoutInterval: 15)
                    req.setValue("Prune/1.0 Sparkle", forHTTPHeaderField: "User-Agent")
                    guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
                    let os = ProcessInfo.processInfo.operatingSystemVersion
                    let osString = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
                    let items = AppcastParser.parse(data).filter { item in
                        item.channel == nil && (item.minOS.map { !Version.isNewer($0, than: osString) } ?? true)
                    }
                    // Escolhe a versão mais recente do appcast.
                    let best = items.max { a, b in
                        let va = a.build ?? a.short ?? "", vb = b.build ?? b.short ?? ""
                        return Version.isNewer(vb, than: va)
                    }
                    guard let best else { return nil }
                    let sameShape = { (a: String, b: String) in Version.numbers(a).count == Version.numbers(b).count }
                    let newer: Bool
                    if let short = best.short, !app.version.isEmpty {
                        let buildNewer = best.build.map { sameShape($0, app.build) && Version.isNewer($0, than: app.build) } ?? false
                        newer = Version.isNewer(short, than: app.version)
                            || (!Version.isNewer(app.version, than: short) && buildNewer)
                    } else if let build = best.build {
                        newer = sameShape(build, app.build)
                            ? Version.isNewer(build, than: app.build)
                            : Version.isNewer(build, than: app.version)
                    } else {
                        newer = false
                    }
                    guard newer else { return nil }
                    return AppUpdate(
                        name: app.name, current: app.version, latest: best.short ?? best.build ?? "?", source: .sparkle,
                        appURL: app.url, downloadURL: best.url.flatMap(URL.init(string:)), notesURL: best.notes.flatMap(URL.init(string:))
                    )
                }
            }
            var result: [AppUpdate] = []
            for await u in group { if let u { result.append(u) } }
            return result
        }
    }

    static var brew: String? { Shell.which(["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]) }

    static func homebrewUpdates() async -> [AppUpdate] {
        guard let brew else { return [] }
        let r = await Shell.run(brew, ["outdated", "--json=v2", "--greedy-auto-updates"], env: ["HOMEBREW_NO_AUTO_UPDATE": "1"])
        guard let data = r.out.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        var result: [AppUpdate] = []
        for cask in json["casks"] as? [[String: Any]] ?? [] {
            let name = cask["name"] as? String ?? "?"
            result.append(AppUpdate(
                name: name, current: (cask["installed_versions"] as? [String])?.first ?? "?",
                latest: cask["current_version"] as? String ?? "?", source: .homebrew, brewName: name
            ))
        }
        for f in json["formulae"] as? [[String: Any]] ?? [] {
            let name = f["name"] as? String ?? "?"
            result.append(AppUpdate(
                name: name, current: (f["installed_versions"] as? [String])?.first ?? "?",
                latest: f["current_version"] as? String ?? "?", source: .homebrewFormula, brewName: name, selected: false
            ))
        }
        return result
    }
}

@MainActor
@Observable
final class UpdaterModel {
    var updates: [AppUpdate] = []
    var checking = false
    var checked = false
    var progressText = ""
    var log: [String] = []
    var installing = false
    var hasBrew: Bool { UpdateService.brew != nil }

    func check() async {
        checking = true
        let reporter = ProgressReporter { [weak self] in self?.progressText = $0 }
        reporter.report("A procurar apps…", force: true)
        let apps = await Task.detached { AppScanner.installedApps(computeSizes: false) }.value
        async let sparkle = UpdateService.sparkleUpdates(apps, progress: reporter)
        reporter.report("A verificar Homebrew…")
        async let brew = UpdateService.homebrewUpdates()
        let (s, b) = await (sparkle, brew)
        // Evita duplicados: se a app é gerida pelo Homebrew, mostra só a entrada do Homebrew.
        let brewNames = Set(b.map { $0.name.lowercased().replacingOccurrences(of: "-", with: " ") })
        updates = b + s.filter { !brewNames.contains($0.name.lowercased()) }
        checking = false
        checked = true
    }

    func updateSelected() async {
        installing = true
        log = []
        for u in updates where u.selected {
            switch u.source {
            case .homebrew, .homebrewFormula:
                guard let brew = UpdateService.brew, let name = u.brewName else { continue }
                log.append("A atualizar \(u.name) com Homebrew…")
                var args = ["upgrade", name]
                if u.source == .homebrew { args.insert("--cask", at: 1) }
                let r = await Shell.run(brew, args, env: ["HOMEBREW_NO_AUTO_UPDATE": "1"])
                log.append(r.ok ? "✓ \(u.name) atualizado para \(u.latest)" : "✗ \(u.name): \(r.err.split(separator: "\n").last ?? "erro")")
                if r.ok { updates.removeAll { $0.id == u.id } }
            case .sparkle:
                // A app trata da atualização através do Sparkle ao abrir; se não, abre a transferência.
                if let app = u.appURL {
                    log.append("A abrir \(u.name) para instalar a atualização…")
                    NSWorkspace.shared.openApplication(at: app, configuration: .init()) { _, _ in }
                } else if let d = u.downloadURL {
                    NSWorkspace.shared.open(d)
                }
            }
        }
        installing = false
    }

    func openAppStoreUpdates() {
        if let url = URL(string: "macappstore://showUpdatesPage") { NSWorkspace.shared.open(url) }
    }
}
