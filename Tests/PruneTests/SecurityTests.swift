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
}
