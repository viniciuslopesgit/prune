import Foundation
import Testing
@testable import Prune

/// Penetration tests: each one plays an attack on what decides what gets deleted, run as root or opened.
/// `scripts/pentest.sh` runs this suite in an isolated environment (no network, writes only in its own
/// temporary folder), so an attack that works cannot reach the real files.
@Suite("Security")
struct SecurityTests {
    static let isolated = ProcessInfo.processInfo.environment["PRUNE_PENTEST"] == "1"

    // MARK: The isolated environment

    @Test("The pentest environment cannot write outside its folder nor reach the network",
          .enabled(if: isolated, "only inside scripts/pentest.sh"))
    func environmentIsIsolated() throws {
        let outside = home.appendingPathComponent(".prune-pentest-canary-\(UUID().uuidString)")
        #expect((try? Data("x".utf8).write(to: outside)) == nil, "wrote to \(outside.path)")
        try? FileManager.default.removeItem(at: outside)
        let r = Shell.runSync("/usr/bin/curl", ["-sS", "-m", "5", "-o", "/dev/null", "https://github.com"])
        #expect(!r.ok, "the network is reachable")
    }

    // MARK: Spelling variants of protected paths

    static let variants = [
        "/SYSTEM", "/system/library", "/USERS", "/applications", "/private/VAR/db/receipts", "/Usr/Bin/ls",
    ]

    @Test("Upper/lower case variants of protected paths are blocked (APFS is case-insensitive)", arguments: variants)
    func caseVariantsOfSystemPaths(_ path: String) {
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: path)))
    }

    @Test("Upper/lower case variants of personal folders are blocked", arguments: ["documents", "DESKTOP", "library/keychains", "Library/mobile documents/x"])
    func caseVariantsOfHomeFolders(_ sub: String) {
        #expect(!SafetyGuard.canDelete(home.appendingPathComponent(sub)))
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: home.path.uppercased()).appendingPathComponent(sub)))
    }

    @Test("Dot segments, double slashes and trailing slashes do not get past the list", arguments: [
        "//System", "/System/.", "/Users/../System", "/tmp/../System/Library", "/Applications/", "/./usr/bin/ls",
    ])
    func pathTricks(_ path: String) {
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: path)))
    }

    @Test("A protected prefix also protects the folder itself, with or without dot segments", arguments: [
        "/private/var/db", "/private/var/db/", "/private/var/db/.", "/private/var/db/x/..", "/var/db/.", "/usr/bin",
        "/usr/bin/.", "/System/Library/..", "/Library/Apple",
    ])
    func prefixFolderItself(_ path: String) {
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: path)))
    }

    @Test("A link to the home folder does not unlock the folders inside it")
    func linkedParent() throws {
        let tmp = try TempDir()
        let link = try tmp.symlink("h", to: home)
        #expect(!SafetyGuard.canDelete(link.appendingPathComponent("Documents")))
        #expect(!SafetyGuard.canDelete(link.appendingPathComponent("library")))
        #expect(SafetyGuard.canDelete(link), "the link itself can go: deleting it does not touch the target")
    }

    @Test("Ignored folders also match in another case")
    func ignoredCaseInsensitive() throws {
        let tmp = try TempDir()
        let keep = try tmp.dir("Keep")
        let before = AppSettings.shared.ignoredPaths
        defer { AppSettings.shared.ignoredPaths = before }
        AppSettings.shared.ignoredPaths = [keep.path]
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: keep.path.uppercased())))
        #expect(!SafetyGuard.canDelete(tmp.path("KEEP/file")))
        #expect(SafetyGuard.canDelete(tmp.path("Keeper")))
    }

    // MARK: Script run as administrator

    /// Runs the administrator script as the current user, in the test folder: same commands, no root.
    private func runAsUser(_ script: String) -> ShellResult { Shell.runSync("/bin/sh", ["-c", script]) }

    @Test("Hostile names reach the administrator script as plain text", arguments: [
        "it's", "a\"b", "$(touch PWNED)", "`touch PWNED`", "x; touch PWNED", "back\\slash", "new\nline", "-rf", "*",
    ])
    func hostileNames(_ name: String) throws {
        let tmp = try TempDir()
        let target = try tmp.file("work/\(name)", "x")
        let neighbour = try tmp.file("work/neighbour", "keep")
        let script = Cleaner.adminScript([target], mode: .permanent)
        // Also through the AppleScript layer: the escaped text must give back the same script.
        let apple = Shell.appleScriptEscape(script)
        #expect(apple.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\") == script)
        _ = runAsUser("cd \(Shell.quote(tmp.path("work").path)) && " + script)
        #expect(!exists(target))
        #expect(read(neighbour) == "keep")
        #expect(!exists(tmp.path("work/PWNED")))
        #expect(!exists(tmp.path("PWNED")))
    }

    @Test("A parent folder swapped for a link after the check does not redirect the deletion (TOCTOU)")
    func swappedParent() throws {
        let tmp = try TempDir()
        let victim = try tmp.file("elsewhere/victim", "precious")
        let target = try tmp.file("cache/victim", "junk")
        let script = Cleaner.adminScript([target], mode: .permanent)
        // The attacker replaces the checked folder with a link to another one before root runs.
        try FileManager.default.removeItem(at: tmp.path("cache"))
        try tmp.symlink("cache", to: tmp.path("elsewhere"))
        _ = runAsUser(script)
        #expect(read(victim) == "precious")
    }

    @Test("A grandparent folder swapped for a link is refused too")
    func swappedGrandparent() throws {
        let tmp = try TempDir()
        let victim = try tmp.file("elsewhere/sub/victim", "precious")
        let target = try tmp.file("cache/sub/victim", "junk")
        let script = Cleaner.adminScript([target], mode: .trash, trash: tmp.path("Trash"))
        try tmp.dir("Trash")
        try FileManager.default.removeItem(at: tmp.path("cache"))
        try tmp.symlink("cache", to: tmp.path("elsewhere"))
        _ = runAsUser(script)
        #expect(read(victim) == "precious")
        #expect(FS.children(tmp.path("Trash")).isEmpty)
    }

    @Test("A link as the item is removed, its target stays")
    func linkItem() throws {
        let tmp = try TempDir()
        let victim = try tmp.file("elsewhere/victim", "precious")
        let link = try tmp.symlink("cache-link", to: tmp.path("elsewhere"))
        _ = runAsUser(Cleaner.adminScript([link], mode: .permanent))
        #expect(!exists(link))
        #expect(read(victim) == "precious")
    }

    @Test("Moving to the Trash as administrator: the item arrives, and a Trash that is a link is refused")
    func adminTrash() throws {
        let tmp = try TempDir()
        let trash = try tmp.dir("Trash")
        let item = try tmp.file("cache/item", "x")
        _ = runAsUser(Cleaner.adminScript([item], mode: .trash, trash: trash))
        #expect(!exists(item))
        #expect(FS.children(trash).map(\.lastPathComponent).allSatisfy { $0.hasPrefix("item ") })
        #expect(FS.children(trash).count == 1)

        let elsewhere = try tmp.dir("elsewhere")
        let fakeTrash = try tmp.symlink("FakeTrash", to: elsewhere)
        let other = try tmp.file("cache/other", "x")
        let script = Cleaner.adminScript([other], mode: .trash, trash: fakeTrash)
        // realpath resolves the link when the script is built; the attacker swaps it afterwards.
        try FileManager.default.removeItem(at: elsewhere)
        try FileManager.default.createSymbolicLink(at: elsewhere, withDestinationURL: tmp.path("cache"))
        _ = runAsUser(script)
        #expect(read(other) == "x", "moved into a Trash that had become a link")
    }

    @Test("Protected paths never make it into the administrator script")
    func adminScriptSkipsProtected() {
        let script = Cleaner.adminScript([URL(fileURLWithPath: "/System"), home.appendingPathComponent("documents"),
                                          URL(fileURLWithPath: "/usr/bin/ls")], mode: .permanent)
        #expect(script.isEmpty)
    }

    // MARK: Shredder

    @Test("Shredding a folder does not overwrite a hard-linked file outside it")
    func shredderHardLinkInFolder() throws {
        let tmp = try TempDir()
        let outside = try tmp.file("outside/precious", bytes: 4096, fill: 7)
        try tmp.dir("shred")
        try FileManager.default.linkItem(at: outside, to: tmp.path("shred/link"))
        try tmp.file("shred/secret", bytes: 4096, fill: 1)
        #expect(Shredder.shredSync(tmp.path("shred"), passes: 1))
        #expect(!exists(tmp.path("shred")))
        #expect(try Data(contentsOf: outside) == Data(repeating: 7, count: 4096))
    }

    @Test("Shredding a hard-linked file only deletes its name here")
    func shredderHardLinkFile() throws {
        let tmp = try TempDir()
        let outside = try tmp.file("outside/precious", "precious")
        let link = tmp.path("link")
        try FileManager.default.linkItem(at: outside, to: link)
        #expect(Shredder.shredSync(link, passes: 2))
        #expect(!exists(link))
        #expect(read(outside) == "precious")
    }

    // MARK: Uninstaller

    @Test("A fake or too short bundle ID does not select other apps' files", arguments: ["e", "com", "", ".", "com.", ".com", "a..b", "*"])
    func hostileBundleID(_ id: String) {
        for entry in ["com.google.Chrome", "Preferences", "com.apple.finder.plist", "e", "group.com.other.shared"] {
            #expect(!AppScanner.isLeftover(entry, bundleID: id, names: []), "\(id) → \(entry)")
        }
    }

    @Test("The bundle ID matches only whole parts of the name")
    func bundleIDBoundaries() {
        let id = "com.foo.app"
        for entry in ["com.foo.app", "com.foo.app.plist", "com.foo.app.savedState", "ABCDE12345.com.foo.app",
                      "group.com.foo.app.shared", "com.foo.app.1234-ABCD.plist", "COM.FOO.APP.binarycookies"] {
            #expect(AppScanner.isLeftover(entry, bundleID: id, names: []), "\(entry)")
        }
        for entry in ["com.foo.application", "com.foo.apple.plist", "xcom.foo.app", "com.foo", "net.com.foo.apps"] {
            #expect(!AppScanner.isLeftover(entry, bundleID: id, names: []), "\(entry)")
        }
        #expect(AppScanner.isLeftover("Foo App.plist", bundleID: id, names: ["foo app"]))
    }

    // MARK: Updater

    @Test("Appcast links only open when they are https", arguments: [
        "file:///Applications/Calculator.app", "http://example.com/app.dmg", "x-apple.systempreferences:com.apple.preference",
        "javascript:alert(1)", "https:///nohost", "ftp://example.com/a.dmg", "/Applications/Calculator.app", "",
    ])
    func appcastSchemes(_ link: String) {
        #expect(UpdateService.webURL(link) == nil)
    }

    @Test("A normal https download link is kept")
    func appcastHttps() {
        #expect(UpdateService.webURL("https://example.com/App-2.0.dmg")?.host == "example.com")
        #expect(UpdateService.webURL("HTTPS://example.com/notes.html") != nil)
        #expect(UpdateService.webURL(nil) == nil)
    }

    // MARK: Scans: links planted in parent folders

    /// A file outside the scanned folders that an attack tries to get offered for deletion.
    private func victim(_ tmp: TempDir) throws -> URL {
        try tmp.file("victim/precious.txt", bytes: 100, fill: 7)
        return tmp.path("victim")
    }

    @Test("A drive whose Trash is a link to another folder does not offer that folder's files")
    func volumeTrashLink() throws {
        let tmp = try TempDir()
        let target = try victim(tmp)
        try tmp.dir("Volumes/USB/.Trashes")
        try tmp.symlink("Volumes/USB/.Trashes/501", to: target)
        try tmp.dir("Volumes/USB2")
        try tmp.symlink("Volumes/USB2/.Trashes", to: tmp.url)
        #expect(TrashScanner.volumeTrashes(in: tmp.path("Volumes"), uid: 501).isEmpty)
    }

    @Test("A Trash that is a link is not emptied")
    func userTrashLink() async throws {
        let tmp = try TempDir()
        let target = try victim(tmp)
        try tmp.symlink(".Trash", to: target)
        let cats = await ScanRoot.$home.withValue(tmp.url) { await TrashScanner.scan(.silent) }
        #expect(cats.flatMap(\.items).isEmpty)
    }

    @Test("A browser profile that is a link to another folder is skipped")
    func chromiumProfileLink() throws {
        let tmp = try TempDir()
        let target = try victim(tmp)
        try tmp.file("victim/History", bytes: 100, fill: 7)
        try tmp.file("victim/Cookies", bytes: 100, fill: 7)
        try tmp.dir("Library/Application Support/Google/Chrome")
        try tmp.symlink("Library/Application Support/Google/Chrome/Default", to: target)
        let chrome = try #require(PrivacyScanner.chromiumBrowsers.first { $0.name == "Google Chrome" })
        let items = inFakeHome(tmp) { PrivacyScanner.chromium(chrome)?.items ?? [] }
        #expect(items.isEmpty, "offered \(items.map(\.url.path))")
    }

    @Test("A Firefox profile that is a link, or a places.sqlite that is a link, is not touched")
    func firefoxLinks() throws {
        let tmp = try TempDir()
        let target = try victim(tmp)
        try tmp.file("victim/places.sqlite", bytes: 100, fill: 7)
        try tmp.file("victim/cookies.sqlite", bytes: 100, fill: 7)
        let profiles = try tmp.dir("Library/Application Support/Firefox/Profiles")
        try tmp.symlink("Library/Application Support/Firefox/Profiles/linked.default", to: target)
        try tmp.dir("Library/Application Support/Firefox/Profiles/real.default")
        try tmp.symlink("Library/Application Support/Firefox/Profiles/real.default/places.sqlite",
                        to: target.appendingPathComponent("places.sqlite"))
        _ = profiles
        let items = inFakeHome(tmp) { PrivacyScanner.firefox()?.items ?? [] }
        #expect(items.isEmpty, "offered \(items.map(\.url.path))")
    }

    @Test("Mail attachments behind a link are not offered")
    func mailAttachmentsLink() async throws {
        let tmp = try TempDir()
        let target = try victim(tmp)
        try tmp.dir("Library/Mail/V10/acct/INBOX.mbox/X/Data/1")
        try tmp.symlink("Library/Mail/V10/acct/INBOX.mbox/X/Data/1/Attachments", to: target)
        try tmp.dir("Library/Containers/com.apple.mail/Data/Library")
        try tmp.symlink("Library/Containers/com.apple.mail/Data/Library/Mail Downloads", to: target)
        let cats = await ScanRoot.$home.withValue(tmp.url) { await MailAttachmentsScanner.scan(.silent) }
        let items = cats.flatMap(\.items)
        #expect(items.isEmpty, "offered \(items.map(\.url.path))")
    }

    @Test("A cache folder that is a link: the link may go, its target stays")
    func cacheLink() async throws {
        let tmp = try TempDir()
        let target = try victim(tmp)
        try tmp.dir("Library/Caches")
        try tmp.symlink("Library/Caches/com.evil.cache", to: target)
        let items = inFakeHome(tmp) { SystemJunkScanner.userCaches(running: []).items }
        _ = await Cleaner.remove(items, mode: .permanent)
        #expect(exists(target.appendingPathComponent("precious.txt")))
    }

    @Test("Hostile Firefox profile names reach sqlite3 as a plain argument", arguments: [
        "x'; DROP TABLE moz_bookmarks; --", "$(touch PWNED)", "`touch PWNED`", "a\"b; touch PWNED", "-cmd .shell touch PWNED",
    ])
    func firefoxHostileProfileName(_ name: String) async throws {
        let tmp = try TempDir()
        let profile = try tmp.dir("Library/Application Support/Firefox/Profiles/\(name)")
        let places = profile.appendingPathComponent("places.sqlite")
        try sqlite(places, """
            CREATE TABLE moz_places (id INTEGER PRIMARY KEY); CREATE TABLE moz_historyvisits (id INTEGER);
            CREATE TABLE moz_inputhistory (id INTEGER); CREATE TABLE moz_bookmarks (fk INTEGER);
            CREATE TABLE moz_annos (place_id INTEGER); INSERT INTO moz_places VALUES (1), (2); INSERT INTO moz_bookmarks VALUES (1);
            """)
        let cat = try #require(inFakeHome(tmp) { PrivacyScanner.firefox() })
        let history = try #require(cat.items.first { $0.url.lastPathComponent == "places.sqlite" })
        let r = await Cleaner.remove([history], mode: .permanent)
        #expect(r.removed == 1)
        #expect(try sqlite(places, "SELECT count(*) FROM moz_bookmarks;") == "1")
        #expect(try sqlite(places, "SELECT group_concat(id) FROM moz_places;") == "1")
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for dir in [tmp.url, profile, cwd] { #expect(!exists(dir.appendingPathComponent("PWNED"))) }
    }

    @Test("A launch agent pointing at a protected program: only its .plist is offered")
    func launchAgentProgramNeverOffered() throws {
        let tmp = try TempDir()
        try tmp.file("Library/LaunchAgents/evil.plist", try plist(["Label": "e", "Program": tmp.path("missing/../../../../System").path]))
        let items = inFakeHome(tmp) { SystemJunkScanner.brokenLaunchAgents().items }
        #expect(items.allSatisfy { $0.url.lastPathComponent == "evil.plist" })
    }

    // MARK: Browser extensions

    @Test("Firefox: an extension path outside the profile's extensions folder is never offered", arguments: [
        "victim", "victim/precious.txt", "PROFILE/extensions/../../../victim", "PROFILE/extensions-evil/x.xpi", "PROFILE/extensions",
    ])
    func firefoxExtensionPath(_ path: String) throws {
        let tmp = try TempDir()
        _ = try victim(tmp)
        let base = "Library/Application Support/Firefox/Profiles"
        let profile = try tmp.dir("\(base)/p.default")
        try tmp.dir("\(base)/p.default/extensions")
        try tmp.file("\(base)/p.default/extensions-evil/x.xpi", bytes: 10, fill: 1)
        let full = path.hasPrefix("PROFILE") ? profile.path + path.dropFirst("PROFILE".count) : tmp.path(path).path
        try tmp.file("\(base)/p.default/extensions.json", try json(["addons": [
            ["id": "evil@x", "type": "extension", "location": "app-profile", "path": full],
        ]]))
        let all = inFakeHome(tmp) { BrowserExtensions.scanAll() }
        #expect(all.isEmpty, "offered \(all.map(\.url.path))")
    }

    @Test("Firefox: an extension that is a link out of the profile is not offered")
    func firefoxExtensionLink() throws {
        let tmp = try TempDir()
        let target = try victim(tmp)
        let base = "Library/Application Support/Firefox/Profiles"
        try tmp.dir("\(base)/p.default/extensions")
        let link = try tmp.symlink("\(base)/p.default/extensions/evil@x", to: target)
        try tmp.file("\(base)/p.default/extensions.json", try json(["addons": [
            ["id": "evil@x", "type": "extension", "location": "app-profile", "path": link.path],
        ]]))
        #expect(inFakeHome(tmp) { BrowserExtensions.scanAll() }.isEmpty)
    }

    @Test("Chromium: extensions of a profile that is a link are not offered")
    func chromiumExtensionProfileLink() throws {
        let tmp = try TempDir()
        try tmp.file("elsewhere/Extensions/abc/1.0/manifest.json", try json(["name": "X", "version": "1"]))
        try tmp.dir("Library/Application Support/Google/Chrome")
        try tmp.symlink("Library/Application Support/Google/Chrome/Default", to: tmp.path("elsewhere"))
        #expect(inFakeHome(tmp) { BrowserExtensions.scanAll() }.isEmpty)
    }

    // MARK: Launch items (run as root)

    static let hostileLabels = ["x'; touch PWNED; '", "$(touch PWNED)", "`touch PWNED`", "a b; touch PWNED", "-rf", "new\nline"]

    @Test("Daemon labels and paths reach launchctl as single arguments", arguments: hostileLabels)
    func daemonScriptArguments(_ label: String) throws {
        let tmp = try TempDir()
        // A fake launchctl records each argument on its own line, so injection would show as extra ones.
        let log = tmp.path("args.log")
        let fake = try tmp.file("bin/launchctl", "#!/bin/sh\nfor a in \"$@\"; do printf '%s\\0' \"$a\" >> \(Shell.quote(log.path)); done; printf '\\036' >> \(Shell.quote(log.path))\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fake.path)
        let plist = try tmp.file("Library/LaunchDaemons/\(label).plist", "x")
        let item = LaunchItem(url: plist, label: label, program: nil, domain: .daemon, loaded: true, disabled: false,
                              programMissing: false, ownerName: "")
        for enabled in [true, false] {
            try? FileManager.default.removeItem(at: log)
            let script = OptimizationService.daemonScript(item, enabled: enabled)
            _ = Shell.runSync("/bin/sh", ["-c", "cd \(Shell.quote(tmp.url.path)) && PATH=\(Shell.quote(tmp.path("bin").path)):$PATH; " + script])
            let calls = (read(log) ?? "").split(separator: "\u{1E}").map { $0.split(separator: "\0", omittingEmptySubsequences: false).dropLast().map(String.init) }
            #expect(calls.count == 2, "\(calls)")
            #expect(calls.contains { $0 == [enabled ? "enable" : "disable", "system/\(label)"] }, "\(calls)")
            #expect(calls.contains { $0.last == plist.path }, "\(calls)")
            #expect(!exists(tmp.path("PWNED")))
        }
    }

    @Test("Removing a launch item deletes only its .plist, whatever its name", arguments: hostileLabels)
    func removeScriptOnlyThePlist(_ name: String) throws {
        let tmp = try TempDir()
        let plist = try tmp.file("LaunchAgents/\(name).plist", "x")
        let neighbour = try tmp.file("LaunchAgents/neighbour.plist", "keep")
        let item = LaunchItem(url: plist, label: name, program: nil, domain: .globalAgent, loaded: false, disabled: false,
                              programMissing: false, ownerName: "")
        _ = Shell.runSync("/bin/sh", ["-c", "cd \(Shell.quote(tmp.url.path)) && " + OptimizationService.removeScript(item)])
        #expect(!exists(plist))
        #expect(read(neighbour) == "keep")
        #expect(!exists(tmp.path("PWNED")) && !exists(tmp.path("LaunchAgents/PWNED")))
    }

    // MARK: Appcasts from the network

    @Test("An appcast with nested entities (billion laughs) does not expand them")
    func billionLaughs() {
        var dtd = "<!ENTITY a0 \"lol\">"
        for i in 1...12 { dtd += "<!ENTITY a\(i) \"" + String(repeating: "&a\(i - 1);", count: 10) + "\">" }
        let xml = """
        <?xml version="1.0"?><!DOCTYPE rss [\(dtd)]>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <sparkle:shortVersionString>&a12;</sparkle:shortVersionString></item></channel></rss>
        """
        let start = Date()
        let items = AppcastParser.parse(Data(xml.utf8))
        #expect(Date().timeIntervalSince(start) < 5)
        #expect(items.allSatisfy { ($0.short?.count ?? 0) < 1_000_000 })
    }

    @Test("An appcast cannot read local files through external entities (XXE)")
    func externalEntities() throws {
        let tmp = try TempDir()
        let secret = try tmp.file("secret.txt", "TOP-SECRET-VALUE")
        let xml = """
        <?xml version="1.0"?><!DOCTYPE rss [<!ENTITY xxe SYSTEM "\(secret.absoluteString)">]>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <sparkle:shortVersionString>&xxe;</sparkle:shortVersionString>
        <sparkle:releaseNotesLink>&xxe;</sparkle:releaseNotesLink></item></channel></rss>
        """
        let items = AppcastParser.parse(Data(xml.utf8))
        #expect(!items.contains { ($0.short ?? "").contains("TOP-SECRET") || ($0.notes ?? "").contains("TOP-SECRET") })
    }

    @Test("Homebrew names that look like options never reach brew upgrade", arguments: [
        "--force", "-x", "", "a b", "x;rm", "$(id)", "../evil",
    ])
    func brewNames(_ name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["casks": [["name": name]], "formulae": [["name": name]]])
        let names = UpdateService.parseOutdated(data).map(\.name)
        if name == "../evil" {
            #expect(names.allSatisfy { !$0.hasPrefix("-") })
        } else {
            #expect(names.isEmpty, "\(names)")
        }
    }

    // MARK: SafetyGuard fuzzing

    @Test("Thousands of spelling variants of protected paths are all refused")
    func safetyGuardFuzz() {
        let protected = ["/System", "/Library", "/Applications", "/Users", "/usr/bin", "/private/var/db",
                         home.path, home.path + "/Documents", home.path + "/Library/Keychains", home.path + "/Desktop"]
        var rng = SplitMix(seed: 2026)
        var tried = 0
        for base in protected {
            for _ in 0..<300 {
                let variant = mutate(base, &rng)
                tried += 1
                #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: variant)), "\(variant)")
            }
        }
        #expect(tried == protected.count * 300)
    }

    /// Changes case, Unicode form, doubles slashes, adds "/." and "x/.." segments or a trailing slash:
    /// every variant still names the same folder on APFS.
    private func mutate(_ path: String, _ rng: inout SplitMix) -> String {
        var parts = path.split(separator: "/").map(String.init)
        for i in parts.indices {
            parts[i] = String(parts[i].map { rng.next() % 2 == 0 ? Character($0.uppercased()) : Character($0.lowercased()) })
            if rng.next() % 4 == 0 { parts[i] = parts[i].decomposedStringWithCanonicalMapping }
        }
        var out = ""
        for p in parts {
            out += rng.next() % 3 == 0 ? "//" : "/"
            out += p
            switch rng.next() % 5 {
            case 0: out += "/."
            case 1: out += "/zz\(rng.next() % 100)/.."
            default: break
            }
        }
        if rng.next() % 2 == 0 { out += "/" }
        return out
    }
}

/// Deterministic pseudo-random numbers: a failing variant is the same on every run.
struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
