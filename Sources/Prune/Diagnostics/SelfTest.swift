import Foundation

/// `Prune --selftest`: runs every scan (read-only) and prints a summary.
enum SelfTest {
    /// `open -n -a Prune.app --args --fdacheck <file>`: writes the result of each Full Disk Access
    /// probe, evaluated with the app's own identity (launched by macOS).
    static func fdaCheckIfRequested() {
        guard let i = CommandLine.arguments.firstIndex(of: "--fdacheck"), i + 1 < CommandLine.arguments.count else { return }
        var lines = ["hasFullDiskAccess=\(Permissions.hasFullDiskAccess)"]
        for p in Permissions.fullDiskAccessProbes {
            lines.append("\(Permissions.probe(p.path, isDirectory: p.isDirectory).rawValue)\t\(p.path)")
        }
        let out = CommandLine.arguments[i + 1]
        Task.detached {
            lines.append("freshProcess=\(await Permissions.hasFullDiskAccessFresh())")
            try? lines.joined(separator: "\n").write(toFile: out, atomically: true, encoding: .utf8)
            exit(0)
        }
    }

    static func runIfRequested() {
        guard CommandLine.arguments.contains("--selftest") else { return }
        // Line by line even when the output goes to a file: if the app crashes, the lines up to the crash stay.
        setvbuf(stdout, nil, _IOLBF, 0)
        Task.detached {
            func time<T>(_ name: String, _ f: () async -> T) async -> T {
                print("  → \(name)")   // before the step: if it crashes, the log says where
                let t = Date()
                let r = await f()
                print(String(format: "  [%5.1fs] %@", Date().timeIntervalSince(t), name))
                return r
            }
            let p = ProgressReporter.silent
            print("Prune self-test (nothing is deleted)")
            // In-process AppleScript runner (the same one used by administrator tasks), without privileges.
            let a = await AppleScriptRunner.shared.run("do shell script \"echo one; echo two\" without altering line endings")
            print("  AppleScript in process: ok=\(a.ok) lines=\(a.out.split(separator: "\n").count) (expected ok=true lines=2)")
            for (name, scan) in [("System Junk", SystemJunkScanner.scan), ("Mail Attachments", MailAttachmentsScanner.scan),
                                 ("Trash Bins", TrashScanner.scan), ("Privacy", PrivacyScanner.scan)] as [(String, (ProgressReporter) async -> [CleanCategory])] {
                let cats = await time(name) { await scan(p) }
                for c in cats where !c.items.isEmpty {
                    print("      \(c.name): \(c.items.count) items, \(Fmt.bytes(c.totalSize)) (selected \(Fmt.bytes(c.selectedSize)))")
                }
            }
            let sec = await time("macOS protections") { await SystemProtection.status() }
            print("      SIP=\(sec.sip.map(String.init) ?? "?") GK=\(sec.gatekeeper.map(String.init) ?? "?") FW=\(sec.firewall.map(String.init) ?? "?") FV=\(sec.fileVault.map(String.init) ?? "?") XProtect=\(sec.xprotectVersion ?? "?")")
            let login = await time("Login items") { await OptimizationService.loginItems() }
            print("      \(login.count) items: \(login.map(\.name).joined(separator: ", "))")
            let agents = await time("Launch agents") { await OptimizationService.launchItems() }
            print("      \(agents.count) agents, \(agents.filter(\.disabled).count) disabled, \(agents.filter(\.programMissing).count) orphaned")
            let procs = await time("Processes") { await OptimizationService.processes() }
            print("      \(procs.count) processes; top CPU: \(procs.sorted { $0.cpu > $1.cpu }.prefix(3).map { "\($0.name) \($0.cpu)%" }.joined(separator: ", "))")
            let apps = await time("Applications") { AppScanner.installedApps() }
            print("      \(apps.count) apps, \(Fmt.bytes(apps.reduce(0) { $0 + $1.size }))")
            if let a = apps.max(by: { $0.size < $1.size }) {
                let l = AppScanner.leftovers(for: a)
                print("      Largest: \(a.name) \(Fmt.bytes(a.size)); leftovers: \(l.count) (\(Fmt.bytes(l.reduce(0) { $0 + $1.size })))")
                for i in l.prefix(6) { print("        - \(i.url.displayPath)") }
            }
            let ids = await AppScanner.allSystemBundleIDs()
            let orphans = await time("Leftovers of removed apps") { AppScanner.orphans(installedIDs: Set(apps.map(\.bundleID)).union(ids)) }
            print("      \(orphans.count) leftovers, \(Fmt.bytes(orphans.reduce(0) { $0 + $1.size }))")
            for o in orphans.prefix(8) { print("        - \(o.url.displayPath) \(Fmt.bytes(o.size))") }
            let ups = await time("Updates (Sparkle)") { await UpdateService.sparkleUpdates(apps, progress: p) }
            for u in ups { print("      \(u.name): \(u.current) → \(u.latest)") }
            let brew = await time("Updates (Homebrew)") { await UpdateService.homebrewUpdates() }
            print("      \(brew.count) outdated packages")
            let exts = await time("Extensions") { await ExtensionService.systemExtensions() }
            print("      \(exts.count) extensions (\(exts.filter { !$0.isSystem }.count) third-party, \(exts.filter { !$0.enabled }.count) disabled)")
            let bext = await time("Browser extensions") { BrowserExtensions.scanAll() }
            for b in bext.prefix(8) { print("      \(b.browser): \(b.name)") }
            let large = await time("Large & Old Files (≥100 MB)") { LargeFilesModel.find(in: [home], minSize: 100_000_000, includeLibrary: false, progress: p) }
            print("      \(large.count) files, \(Fmt.bytes(large.reduce(0) { $0 + $1.size }))")
            let dups = await time("Duplicates (Downloads)") { DuplicateFinder.find(in: [URL.home("Downloads")], minSize: 100_000, progress: p) }
            print("      \(dups.count) groups, \(Fmt.bytes(dups.reduce(0) { $0 + $1.wasted })) wasted")
            let space = await time("Space Lens (Downloads)") { SpaceScanner(progress: p).scan(URL.home("Downloads")) }
            print("      \(Fmt.bytes(space.size)), \(space.children.count) children; largest: \(space.children.first?.name ?? "-")")
            let rects = Treemap.layout(sizes: [6, 6, 4, 3, 2, 2, 1], in: CGRect(x: 0, y: 0, width: 600, height: 400))
            let area = rects.reduce(0) { $0 + $1.width * $1.height }
            print("  Treemap: total area \(Int(area)) (expected 240000)")
            print("  Versions: \(Version.isNewer("1.10.2", than: "1.9")) \(Version.isNewer("2.0", than: "2.0.0")) \(Version.isNewer("1.2", than: "1.10"))  (expected true false false)")
            let mustBlock = ["/", "/System", home.path, home.path + "/Documents", home.path + "/Library", "/Applications", "/usr/bin/ls"]
            let blocked = mustBlock.allSatisfy { !SafetyGuard.canDelete(URL(fileURLWithPath: $0)) }
            print("  SafetyGuard blocks critical folders: \(blocked)")
            let viaSymlink = !SafetyGuard.canDelete(URL(fileURLWithPath: "/var/db/test"))
            print("  SafetyGuard resolves links (/var/db → /private/var/db): \(viaSymlink)")
            print("  Shredder does not follow symbolic links: \(shredderKeepsSymlinkTarget())")
            // The interface really came up (on macOS 12, or with PRUNE_LEGACY_UI=1, through AppKit).
            let ui = await MainActor.run { () -> (window: Bool, menuBar: Bool) in
                (WindowOpener.shared.mainWindow != nil, !PruneMain.legacyUI || !BackgroundMode.menuBarEnabled || LegacyMenuBar.shared.isInstalled)
            }
            print("  Interface: legacy=\(PruneMain.legacyUI) window=\(ui.window) menuBar=\(ui.menuBar)")
            exit(0)
        }
    }

    /// Shreds a folder holding a link to a file outside it and confirms the file stays intact.
    private static func shredderKeepsSymlinkTarget() -> Bool {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("prune-selftest-\(UUID().uuidString)")
        let target = base.appendingPathComponent("original.txt")
        let folder = base.appendingPathComponent("to-shred")
        defer { try? fm.removeItem(at: base) }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try "original content".write(to: target, atomically: true, encoding: .utf8)
            try fm.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: target)
        } catch { return false }
        _ = Shredder.shredSync(folder, passes: 1)
        return !folder.exists && (try? String(contentsOf: target, encoding: .utf8)) == "original content"
    }
}
