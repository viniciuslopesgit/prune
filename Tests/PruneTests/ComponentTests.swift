import Foundation
import Testing
@testable import Prune

func app(version: String, build: String, name: String = "Demo") -> AppInfo {
    AppInfo(url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, bundleID: "com.demo.app", version: version,
            build: build, size: 0, lastUsed: nil, isAppStore: false, vendor: "Demo", feedURL: nil)
}

func appcast(_ items: String) -> Data {
    Data("""
    <?xml version="1.0"?>
    <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel>\(items)</channel></rss>
    """.utf8)
}

@Suite("Updater")
struct UpdaterTests {
    @Test("Versions compare number by number", arguments: [
        ("1.10.2", "1.9", true), ("2.0", "1.99.99", true), ("1.0", "1.0.0", false), ("1.0.1", "1.0", true),
        ("1.2", "1.10", false), ("v3", "2", true), ("", "1", false), ("1", "", false), ("abc", "1", false),
        ("99999999999999999999999", "1", false),
    ] as [(String, String, Bool)])
    func versions(_ a: String, _ b: String, _ newer: Bool) {
        #expect(Version.isNewer(a, than: b) == newer)
    }

    @Test("The newest stable item that runs on this macOS is offered")
    func newestStable() throws {
        let data = appcast("""
            <item><sparkle:version>200</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString>
                <enclosure url="https://example.com/2.0.dmg"/></item>
            <item><sparkle:version>300</sparkle:version><sparkle:shortVersionString>3.0-beta</sparkle:shortVersionString>
                <sparkle:channel>beta</sparkle:channel><enclosure url="https://example.com/3.dmg"/></item>
            <item><sparkle:version>250</sparkle:version><sparkle:shortVersionString>2.5</sparkle:shortVersionString>
                <sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion></item>
            <item><enclosure url="https://example.com/1.dmg" sparkle:version="100" sparkle:shortVersionString="1.0"/></item>
            """)
        let u = try #require(UpdateService.update(for: app(version: "1.5", build: "150"), appcast: data, osVersion: "14.5.0"))
        #expect(u.latest == "2.0" && u.current == "1.5" && u.source == .sparkle)
        #expect(u.downloadURL?.absoluteString == "https://example.com/2.0.dmg")
    }

    @Test("Nothing is offered when the installed version is the newest")
    func upToDate() {
        let data = appcast("<item><sparkle:version>150</sparkle:version><sparkle:shortVersionString>1.5</sparkle:shortVersionString></item>")
        #expect(UpdateService.update(for: app(version: "1.5", build: "150"), appcast: data, osVersion: "14.0") == nil)
        #expect(UpdateService.update(for: app(version: "2.0", build: "200"), appcast: data, osVersion: "14.0") == nil)
    }

    @Test("Same version with a newer build is an update; a build of another shape is not")
    func newerBuild() {
        let data = appcast("<item><sparkle:version>151</sparkle:version><sparkle:shortVersionString>1.5</sparkle:shortVersionString></item>")
        #expect(UpdateService.update(for: app(version: "1.5", build: "150"), appcast: data, osVersion: "14.0") != nil)
        let other = appcast("<item><sparkle:version>2024.1.1</sparkle:version><sparkle:shortVersionString>1.5</sparkle:shortVersionString></item>")
        #expect(UpdateService.update(for: app(version: "1.5", build: "150"), appcast: other, osVersion: "14.0") == nil)
    }

    @Test("Links in the appcast that are not https are dropped, the update stays")
    func unsafeLinks() throws {
        let data = appcast("""
            <item><sparkle:version>9</sparkle:version><sparkle:shortVersionString>9</sparkle:shortVersionString>
            <sparkle:releaseNotesLink>file:///etc/passwd</sparkle:releaseNotesLink><enclosure url="http://x/a.dmg"/></item>
            """)
        let u = try #require(UpdateService.update(for: app(version: "1", build: "1"), appcast: data, osVersion: "14.0"))
        #expect(u.downloadURL == nil && u.notesURL == nil)
    }

    @Test("Broken or empty appcasts give no update", arguments: ["", "<rss>", "not xml at all", "<item></item>"])
    func brokenAppcast(_ text: String) {
        #expect(UpdateService.update(for: app(version: "1", build: "1"), appcast: Data(text.utf8), osVersion: "14.0") == nil)
    }

    @Test("Homebrew: apps selected, command-line tools not")
    func homebrew() throws {
        let data = try json([
            "casks": [["name": "firefox", "installed_versions": ["130.0"], "current_version": "131.0"]],
            "formulae": [["name": "wget", "installed_versions": ["1.24"], "current_version": "1.25"]],
        ])
        let all = UpdateService.parseOutdated(data)
        #expect(all.map(\.name) == ["firefox", "wget"])
        #expect(all.map(\.selected) == [true, false])
        #expect(all[0].current == "130.0" && all[0].latest == "131.0" && all[0].brewName == "firefox")
        #expect(UpdateService.parseOutdated(Data("garbage".utf8)).isEmpty)
    }
}

@Suite("Optimization")
struct OptimizationTests {
    @Test("Disabled services from launchctl print-disabled")
    func disabled() {
        let out = """
        disabled services = {
            "com.vendor.agent" => disabled
            "com.vendor.on" => enabled
            "com.other.old" => true
            "com.other.fine" => false
        }
        """
        #expect(OptimizationService.parseDisabled(out) == ["com.vendor.agent", "com.other.old"])
        #expect(OptimizationService.parseDisabled("").isEmpty)
    }

    @Test("Owner name: the app the program is in, else the label's vendor")
    func ownerName() {
        #expect(OptimizationService.ownerName(label: "x", program: "/Applications/Zoom.app/Contents/MacOS/helper") == "Zoom")
        #expect(OptimizationService.ownerName(label: "com.dropbox.agent", program: "/usr/local/bin/d") == "Dropbox")
        #expect(OptimizationService.ownerName(label: "single", program: nil) == "single")
    }
}

@Suite("Maintenance")
struct MaintenanceTests {
    @Test("Exit codes come back per task")
    func exitCodes() {
        #expect(MaintenanceModel.exitCodes("dns:0\nspotlight:1\nnoise\na:b:c\n") == ["dns": "0", "spotlight": "1"])
    }

    @Test("The administrator script reports every task, even when one fails")
    func adminScript() {
        let tasks = [
            MaintenanceTask(id: "ok", title: "", icon: "", description: "", requiresAdmin: true, command: "true", recommendedDays: 1),
            MaintenanceTask(id: "bad", title: "", icon: "", description: "", requiresAdmin: true, command: "echo noise; exit 3", recommendedDays: 1),
            MaintenanceTask(id: "last", title: "", icon: "", description: "", requiresAdmin: true, command: "false", recommendedDays: 1),
        ]
        let r = Shell.runSync("/bin/sh", ["-c", MaintenanceModel.adminScript(tasks)])
        #expect(MaintenanceModel.exitCodes(r.out) == ["ok": "0", "bad": "3", "last": "1"])
        #expect(!r.out.contains("noise"))
    }

    @Test("Every catalog task has a unique id that the exit-code lines can carry")
    func catalog() {
        let ids = MaintenanceCatalog.tasks.map(\.id)
        #expect(Set(ids).count == ids.count)
        for t in MaintenanceCatalog.tasks {
            #expect(!t.id.isEmpty && !t.id.contains(":") && !t.id.contains("\n"), "\(t.id)")
            #expect(t.recommendedDays >= 0)
            #expect(!t.command.isEmpty)
        }
    }
}

@Suite("Duplicates selection")
struct DuplicatesSelectionTests {
    func group(_ tmp: TempDir, _ names: [String], similar: Bool = false) throws -> DupGroup {
        DupGroup(files: try names.map { DupFile(url: try tmp.file($0, "same"), size: 4, created: nil, modified: nil) }, similar: similar)
    }

    @Test("Auto-select keeps the first copy of each group and never picks similar photos")
    func autoSelect() throws {
        let tmp = try TempDir()
        let exact = try group(tmp, ["a1", "a2", "a3"])
        let similar = try group(tmp, ["p1.jpg", "p2.jpg"], similar: true)
        let marked = DuplicatesModel.autoMarked([exact, similar])
        #expect(marked == [exact.files[1].id, exact.files[2].id])
    }

    @Test("Even with every copy marked, one copy always stays")
    func neverAll() throws {
        let tmp = try TempDir()
        let g = try group(tmp, ["b1", "b2"])
        let all = Set(g.files.map(\.id))
        #expect(DuplicatesModel.toRemove([g], marked: all).map(\.lastPathComponent) == ["b2"])
        #expect(DuplicatesModel.toRemove([g], marked: [g.files[0].id]).map(\.lastPathComponent) == ["b1"])
        #expect(DuplicatesModel.toRemove([g], marked: []).isEmpty)
    }

    @Test("Removing duplicates deletes only the marked copies and keeps one per group")
    @MainActor
    func removeMarked() async throws {
        let tmp = try TempDir()
        let g1 = try group(tmp, ["c1", "c2", "c3"]), g2 = try group(tmp, ["d1", "d2"])
        let model = DuplicatesModel()
        model.groups = [g1, g2]
        model.marked = Set(g1.files.map(\.id) + g2.files.map(\.id))
        let settings = AppSettings.shared
        let previous = settings.filesDeleteMode
        settings.filesDeleteMode = .permanent   // never the real Trash
        defer { settings.filesDeleteMode = previous }
        await model.removeMarked()
        #expect(exists(g1.files[0].url) && exists(g2.files[0].url))
        #expect(!exists(g1.files[1].url) && !exists(g1.files[2].url) && !exists(g2.files[1].url))
        #expect(model.groups.isEmpty)
        #expect(model.marked.isEmpty)
    }
}

@Suite("Cleanup flow")
@MainActor
struct CleanupFlowTests {
    func model(_ tmp: TempDir) throws -> CleanupModel {
        let keep = try tmp.file("cat/keep.log", bytes: 10, fill: 1)
        let drop = try tmp.file("cat/drop.log", bytes: 20, fill: 1)
        let items = [CleanItem(url: drop, size: 20), CleanItem(url: keep, size: 10, selected: false)]
        return CleanupModel(mode: { .permanent }, scanner: { _ in
            [CleanCategory(id: "c", name: "C", icon: "", info: "", items: items)]
        })
    }

    @Test("Scan, then clean: only the selected items go, totals follow the selection")
    func flow() async throws {
        let tmp = try TempDir()
        let m = try model(tmp)
        await m.scan()
        #expect(m.phase == .results)
        #expect(m.totalSize == 30 && m.selectedSize == 20 && m.selectedCount == 1)
        await m.clean()
        #expect(!exists(tmp.path("cat/drop.log")))
        #expect(exists(tmp.path("cat/keep.log")))
        #expect(m.report.removed == 1 && m.report.freed == 20)
    }

    @Test("Toggling a category selects all of it, then none")
    func toggleCategory() async throws {
        let tmp = try TempDir()
        let m = try model(tmp)
        await m.scan()
        m.toggleCategory("c")
        #expect(m.selectedCount == 2)
        m.toggleCategory("c")
        #expect(m.selectedCount == 0)
        await m.clean()
        #expect(exists(tmp.path("cat/drop.log")) && exists(tmp.path("cat/keep.log")))
    }
}
