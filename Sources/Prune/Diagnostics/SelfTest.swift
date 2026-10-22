import Foundation

/// `Prune --selftest`: executa todas as análises (só leitura) e imprime um resumo.
enum SelfTest {
    /// `open -n -a Prune.app --args --fdacheck <ficheiro>`: escreve o resultado de cada teste
    /// de Acesso Total ao Disco, avaliado com a identidade da própria app (lançada pelo macOS).
    static func fdaCheckIfRequested() {
        guard let i = CommandLine.arguments.firstIndex(of: "--fdacheck"), i + 1 < CommandLine.arguments.count else { return }
        var lines = ["hasFullDiskAccess=\(Permissions.hasFullDiskAccess)"]
        for p in Permissions.fullDiskAccessProbes {
            lines.append("\(Permissions.probe(p.path, isDirectory: p.isDirectory).rawValue)\t\(p.path)")
        }
        let out = CommandLine.arguments[i + 1]
        Task.detached {
            lines.append("processoNovo=\(await Permissions.hasFullDiskAccessFresh())")
            try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
            exit(0)
        }
    }

    static func runIfRequested() {
        guard CommandLine.arguments.contains("--selftest") else { return }
        Task.detached {
            func time<T>(_ name: String, _ f: () async -> T) async -> T {
                let t = Date()
                let r = await f()
                print(String(format: "  [%5.1fs] %@", Date().timeIntervalSince(t), name))
                return r
            }
            let p = ProgressReporter.silent
            print("Prune self-test (nada é apagado)")
            // Executor de AppleScript em processo (o mesmo das tarefas de administrador), sem privilégios.
            let a = await AppleScriptRunner.shared.run("do shell script \"echo um; echo dois\" without altering line endings")
            print("  AppleScript em processo: ok=\(a.ok) linhas=\(a.out.split(separator: "\n").count) (esperado ok=true linhas=2)")
            for (name, scan) in [("Lixo do Sistema", SystemJunkScanner.scan), ("Anexos do Mail", MailAttachmentsScanner.scan),
                                 ("Lixo", TrashScanner.scan), ("Privacidade", PrivacyScanner.scan)] as [(String, (ProgressReporter) async -> [CleanCategory])] {
                let cats = await time(name) { await scan(p) }
                for c in cats where !c.items.isEmpty {
                    print("      \(c.name): \(c.items.count) itens, \(Fmt.bytes(c.totalSize)) (selecionado \(Fmt.bytes(c.selectedSize)))")
                }
            }
            let sec = await time("Proteções do macOS") { await SystemProtection.status() }
            print("      SIP=\(sec.sip.map(String.init) ?? "?") GK=\(sec.gatekeeper.map(String.init) ?? "?") FW=\(sec.firewall.map(String.init) ?? "?") FV=\(sec.fileVault.map(String.init) ?? "?") XProtect=\(sec.xprotectVersion ?? "?")")
            let login = await time("Itens de início de sessão") { await OptimizationService.loginItems() }
            print("      \(login.count) itens: \(login.map(\.name).joined(separator: ", "))")
            let agents = await time("Agentes de arranque") { await OptimizationService.launchItems() }
            print("      \(agents.count) agentes, \(agents.filter(\.disabled).count) desativados, \(agents.filter(\.programMissing).count) órfãos")
            let procs = await time("Processos") { await OptimizationService.processes() }
            print("      \(procs.count) processos; top CPU: \(procs.sorted { $0.cpu > $1.cpu }.prefix(3).map { "\($0.name) \($0.cpu)%" }.joined(separator: ", "))")
            let apps = await time("Aplicações") { AppScanner.installedApps() }
            print("      \(apps.count) apps, \(Fmt.bytes(apps.reduce(0) { $0 + $1.size }))")
            if let a = apps.max(by: { $0.size < $1.size }) {
                let l = AppScanner.leftovers(for: a)
                print("      Maior: \(a.name) \(Fmt.bytes(a.size)); restos: \(l.count) (\(Fmt.bytes(l.reduce(0) { $0 + $1.size })))")
                for i in l.prefix(6) { print("        - \(i.url.displayPath)") }
            }
            let ids = await AppScanner.allSystemBundleIDs()
            let orphans = await time("Restos de apps removidas") { AppScanner.orphans(installedIDs: Set(apps.map(\.bundleID)).union(ids)) }
            print("      \(orphans.count) restos, \(Fmt.bytes(orphans.reduce(0) { $0 + $1.size }))")
            for o in orphans.prefix(8) { print("        - \(o.url.displayPath) \(Fmt.bytes(o.size))") }
            let ups = await time("Atualizações (Sparkle)") { await UpdateService.sparkleUpdates(apps, progress: p) }
            for u in ups { print("      \(u.name): \(u.current) → \(u.latest)") }
            let brew = await time("Atualizações (Homebrew)") { await UpdateService.homebrewUpdates() }
            print("      \(brew.count) pacotes desatualizados")
            let exts = await time("Extensões") { await ExtensionService.systemExtensions() }
            print("      \(exts.count) extensões (\(exts.filter { !$0.isSystem }.count) de terceiros, \(exts.filter { !$0.enabled }.count) desativadas)")
            let bext = await time("Extensões de navegadores") { BrowserExtensions.scanAll() }
            for b in bext.prefix(8) { print("      \(b.browser): \(b.name)") }
            let large = await time("Grandes e Antigos (≥100 MB)") { LargeFilesModel.find(in: [home], minSize: 100_000_000, includeLibrary: false, progress: p) }
            print("      \(large.count) ficheiros, \(Fmt.bytes(large.reduce(0) { $0 + $1.size }))")
            let dups = await time("Duplicados (Downloads)") { DuplicateFinder.find(in: [URL.home("Downloads")], minSize: 100_000, progress: p) }
            print("      \(dups.count) grupos, \(Fmt.bytes(dups.reduce(0) { $0 + $1.wasted })) desperdiçados")
            let space = await time("Lente de Espaço (Downloads)") { SpaceScanner(progress: p).scan(URL.home("Downloads")) }
            print("      \(Fmt.bytes(space.size)), \(space.children.count) filhos; maior: \(space.children.first?.name ?? "-")")
            let rects = Treemap.layout(sizes: [6, 6, 4, 3, 2, 2, 1], in: CGRect(x: 0, y: 0, width: 600, height: 400))
            let area = rects.reduce(0) { $0 + $1.width * $1.height }
            print("  Treemap: área total \(Int(area)) (esperado 240000)")
            print("  Versões: \(Version.isNewer("1.10.2", than: "1.9")) \(Version.isNewer("2.0", than: "2.0.0")) \(Version.isNewer("1.2", than: "1.10"))  (esperado true false false)")
            let mustBlock = ["/", "/System", home.path, home.path + "/Documents", home.path + "/Library", "/Applications", "/usr/bin/ls"]
            let blocked = mustBlock.allSatisfy { !SafetyGuard.canDelete(URL(fileURLWithPath: $0)) }
            print("  SafetyGuard bloqueia pastas críticas: \(blocked)")
            exit(0)
        }
    }
}
