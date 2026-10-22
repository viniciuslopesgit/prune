import AppKit
import Foundation

/// Lixo do Sistema: caches, logs, temporários, lixo de programação, preferências danificadas…
enum SystemJunkScanner {
    /// Caches que não devem ser removidos com a app/sistema a usá-los.
    static let cacheExclusions: Set<String> = [
        "CloudKit", "com.apple.bird", "com.apple.akd", "FamilyCircle", "com.apple.homed",
        "com.apple.containermanagerd", "com.apple.ap.adprivacyd", "com.apple.Safari.SafeBrowsing",
        "com.apple.nsservicescache", "com.apple.iCloudHelper", "Prune", "app.prune.Prune", "com.apple.amsengagementd",
        "com.apple.ctcategories", "GeoServices",
    ]

    static func scan(_ p: ProgressReporter) async -> [CleanCategory] {
        let lib = URL.home("Library")
        var cats: [CleanCategory] = []

        p.report("A analisar caches do utilizador…", force: true)
        cats.append(CleanCategory(
            id: "userCache", name: "Caches do utilizador", icon: "shippingbox",
            info: "Ficheiros temporários criados pelas apps para acelerar o carregamento. São recriados quando necessário.",
            items: FS.childItems(of: lib.appendingPathComponent("Caches"), excluding: cacheExclusions.union(["Homebrew", "pip", "Yarn", "CocoaPods", "node-gyp", "ms-playwright", "com.apple.dt.Xcode"]))
        ))

        // Caches de apps abertas não ficam selecionados (podem estar a ser usados).
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        if let i = cats.firstIndex(where: { $0.id == "userCache" }) {
            for j in cats[i].items.indices where running.contains(cats[i].items[j].name.lowercased()) {
                cats[i].items[j].selected = false
                cats[i].items[j].detail = "App aberta — feche-a para limpar com segurança"
            }
        }

        p.report("A analisar caches do sistema…")
        cats.append(CleanCategory(
            id: "systemCache", name: "Caches do sistema", icon: "gearshape.2",
            info: "Caches partilhados por todas as contas. Alguns podem requerer a palavra-passe de administrador.",
            items: FS.childItems(of: URL(fileURLWithPath: "/Library/Caches"), excluding: ["com.apple.iconservices", "com.apple.amsd"])
        ))

        p.report("A analisar registos (logs)…")
        cats.append(CleanCategory(
            id: "userLogs", name: "Registos do utilizador", icon: "doc.text",
            info: "Registos de atividade das apps. Úteis apenas para diagnóstico.",
            items: FS.childItems(of: lib.appendingPathComponent("Logs"), excluding: ["DiagnosticReports"])
        ))
        cats.append(CleanCategory(
            id: "systemLogs", name: "Registos do sistema", icon: "doc.text.fill",
            info: "Registos de serviços do sistema e instaladores.",
            items: FS.childItems(of: URL(fileURLWithPath: "/Library/Logs"), excluding: ["DiagnosticReports"])
        ))

        p.report("A analisar relatórios de falhas…")
        cats.append(CleanCategory(
            id: "crash", name: "Relatórios de falhas", icon: "exclamationmark.triangle",
            info: "Relatórios gerados quando uma app falha ou bloqueia.",
            items: FS.childItems(of: lib.appendingPathComponent("Logs/DiagnosticReports"))
                + FS.childItems(of: URL(fileURLWithPath: "/Library/Logs/DiagnosticReports"))
        ))

        p.report("A analisar ficheiros temporários…")
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        let twoDaysAgo = Date().addingTimeInterval(-2 * 86400)
        cats.append(CleanCategory(
            id: "temp", name: "Ficheiros temporários", icon: "clock.arrow.circlepath",
            info: "Ficheiros temporários com mais de 2 dias que as apps deixaram para trás.",
            items: FS.childItems(of: tmp, excluding: ["Prune", "app.prune.Prune", "com.apple"], olderThan: twoDaysAgo)
        ))

        p.report("A analisar lixo do Xcode…")
        cats.append(xcodeJunk())

        p.report("A analisar caches de programação…")
        cats.append(devCaches())

        p.report("A analisar atualizações e cópias de segurança de iPhone/iPad…")
        cats.append(iosFiles())

        p.report("A procurar preferências danificadas…")
        cats.append(brokenPreferences())

        p.report("A procurar itens de arranque quebrados…")
        cats.append(brokenLaunchAgents())

        p.report("A analisar caches de transferências…")
        cats.append(downloadsJunk())

        return cats
    }

    static func xcodeJunk() -> CleanCategory {
        let dev = URL.home("Library/Developer")
        var items: [CleanItem] = []
        if let i = FS.item(dev.appendingPathComponent("Xcode/DerivedData"), name: "DerivedData", detail: "Ficheiros de compilação intermédios") { items.append(i) }
        if let i = FS.item(URL.home("Library/Caches/com.apple.dt.Xcode"), name: "Cache do Xcode") { items.append(i) }
        for sub in ["iOS DeviceSupport", "watchOS DeviceSupport", "tvOS DeviceSupport", "visionOS DeviceSupport"] {
            items += FS.childItems(of: dev.appendingPathComponent("Xcode/\(sub)"), detail: "Símbolos de \(sub.replacingOccurrences(of: " DeviceSupport", with: ""))")
        }
        if let i = FS.item(dev.appendingPathComponent("CoreSimulator/Caches"), name: "Caches do Simulador") { items.append(i) }
        if let i = FS.item(dev.appendingPathComponent("Xcode/UserData/Previews"), name: "Pré-visualizações SwiftUI") { items.append(i) }
        items += FS.childItems(of: dev.appendingPathComponent("Xcode/Archives"), selected: false, detail: "Arquivo de compilação — confirme antes de remover")
        return CleanCategory(
            id: "xcode", name: "Lixo do Xcode", icon: "hammer",
            info: "Dados de compilação, símbolos de dispositivos e caches do simulador. Os arquivos (Archives) não estão selecionados por defeito.",
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
            id: "dev", name: "Caches de programação", icon: "chevron.left.forwardslash.chevron.right",
            info: "Pacotes descarregados por gestores como npm, pip, Homebrew ou Gradle. São descarregados de novo quando necessário.",
            items: items
        )
    }

    static func iosFiles() -> CleanCategory {
        var items: [CleanItem] = []
        for sub in ["iPhone Software Updates", "iPad Software Updates", "iPod Software Updates"] {
            items += FS.childItems(of: URL.home("Library/iTunes/\(sub)"), detail: "Ficheiro de atualização (IPSW)")
        }
        let backups = FS.childItems(of: URL.home("Library/Application Support/MobileSync/Backup"), selected: false, detail: "Cópia de segurança de dispositivo")
        items += backups.map { item in
            var i = item
            let info = item.url.appendingPathComponent("Info.plist")
            if let dict = NSDictionary(contentsOf: info), let name = dict["Device Name"] as? String {
                let date = (dict["Last Backup Date"] as? Date).map { " — " + Fmt.date($0) } ?? ""
                i.name = "Cópia de segurança: \(name)\(date)"
            }
            return i
        }
        return CleanCategory(
            id: "ios", name: "Ficheiros de iPhone/iPad", icon: "iphone",
            info: "Atualizações de firmware descarregadas e cópias de segurança antigas. As cópias de segurança nunca são selecionadas automaticamente.",
            items: items,
            warning: backups.isEmpty ? nil : "Remover uma cópia de segurança apaga-a de forma permanente."
        )
    }

    static func brokenPreferences() -> CleanCategory {
        let prefs = URL.home("Library/Preferences")
        var items: [CleanItem] = []
        let files = FS.children(prefs) + FS.children(prefs.appendingPathComponent("ByHost"))
        for url in files where url.pathExtension == "plist" {
            guard let data = try? Data(contentsOf: url) else { continue }
            if data.isEmpty || (try? PropertyListSerialization.propertyList(from: data, format: nil)) == nil {
                items.append(CleanItem(url: url, size: max(Int64(data.count), 4096), detail: "Não é possível ler este ficheiro de preferências"))
            }
        }
        return CleanCategory(
            id: "brokenPrefs", name: "Preferências danificadas", icon: "wrench.and.screwdriver",
            info: "Ficheiros .plist corrompidos que podem causar comportamentos estranhos nas apps.",
            items: items
        )
    }

    static func brokenLaunchAgents() -> CleanCategory {
        let dir = URL.home("Library/LaunchAgents")
        var items: [CleanItem] = []
        for url in FS.children(dir) where url.pathExtension == "plist" {
            guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
                items.append(CleanItem(url: url, size: 4096, detail: "Ficheiro ilegível"))
                continue
            }
            if let program = LaunchItemParser.program(of: dict), !program.hasPrefix("/usr/bin"), !program.hasPrefix("/bin"),
               program.hasPrefix("/"), !FileManager.default.fileExists(atPath: program) {
                items.append(CleanItem(url: url, size: 4096, detail: "O programa já não existe: \(program)"))
            }
        }
        return CleanCategory(
            id: "brokenAgents", name: "Itens de arranque quebrados", icon: "bolt.slash",
            info: "Agentes de arranque que apontam para programas que já foram removidos.",
            items: items
        )
    }

    static func downloadsJunk() -> CleanCategory {
        let downloads = URL.home("Downloads")
        let items = FS.children(downloads).filter {
            ["download", "crdownload", "part", "partial", "opdownload"].contains($0.pathExtension.lowercased())
        }.compactMap { FS.item($0, detail: "Transferência incompleta") }
        return CleanCategory(
            id: "partialDownloads", name: "Transferências incompletas", icon: "arrow.down.circle.dotted",
            info: "Ficheiros de transferências que foram interrompidas ou falharam.",
            items: items
        )
    }
}

enum LaunchItemParser {
    static func program(of dict: [String: Any]) -> String? {
        if let p = dict["Program"] as? String { return p }
        if let args = dict["ProgramArguments"] as? [String], let first = args.first { return first }
        return nil
    }
}
