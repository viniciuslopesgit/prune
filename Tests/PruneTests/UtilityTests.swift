import Foundation
import Testing
@testable import Prune

@Suite("Versions")
struct VersionTests {
    @Test("Numeric comparison", arguments: [
        ("1.10.2", "1.9", true), ("2.0", "2.0.0", false), ("1.2", "1.10", false), ("1.2.5", "1.2.4", true),
        ("1.2.4", "1.2.5", false), ("10", "9.9.9", true), ("v2.1", "2.0", true), ("1.0 (45)", "1.0 (44)", true),
        ("", "1.0", false), ("1.0", "", false), ("beta", "1.0", false), ("1.0.1", "1.0", true),
    ])
    func isNewer(_ a: String, _ b: String, _ expected: Bool) {
        #expect(Version.isNewer(a, than: b) == expected)
    }

    @Test("Is never newer than itself")
    func irreflexive() {
        for v in ["1", "1.2", "1.2.3", "0.0.1"] { #expect(!Version.isNewer(v, than: v)) }
    }

    @Test func numbers() {
        #expect(Version.numbers("1.2.3-beta4") == [1, 2, 3, 4])
        #expect(Version.numbers("abc").isEmpty)
    }
}

@Suite("Formatting")
struct FormattingTests {
    @Test("Plurals", arguments: [(0, "0 items"), (1, "1 item"), (2, "2 items"), (1000, "1000 items")])
    func count(_ n: Int, _ expected: String) {
        #expect(Fmt.count(n, "item", "items") == expected)
        #expect(Fmt.items(n) == expected)
    }

    @Test func files() {
        #expect(Fmt.files(1) == "1 file")
        #expect(Fmt.files(3) == "3 files")
    }

    @Test("Freed space message, with the files that could not be removed")
    func freedMessage() {
        let size = Fmt.bytes(2_000_000)
        #expect(Fmt.freedMessage(2_000_000, failed: 0) == "\(size) freed.")
        #expect(Fmt.freedMessage(2_000_000, failed: 1) == "\(size) freed. 1 file was not removed.")
        #expect(Fmt.freedMessage(2_000_000, failed: 4) == "\(size) freed. 4 files were not removed.")
    }

    @Test func percent() {
        #expect(Fmt.percent(0) == "0%")
        #expect(Fmt.percent(0.426) == "43%")
        #expect(Fmt.percent(1) == "100%")
    }

    @Test func emptyDates() {
        #expect(Fmt.date(nil) == "—")
        #expect(Fmt.relative(nil) == "never")
        #expect(!Fmt.date(Date()).isEmpty)
    }

    @Test("Dates follow the interface language, not a fixed language")
    func datesFollowLanguage() {
        let day = Date(timeIntervalSince1970: 1_792_670_400)  // 22 October 2026
        #expect(Fmt.date(day, locale: Locale(identifier: "en_US")).contains("Oct"))
        #expect(Fmt.date(day, locale: Locale(identifier: "pt_PT")) != Fmt.date(day, locale: Locale(identifier: "en_US")))
        let threeDaysAgo = Date().addingTimeInterval(-3 * 86_400)
        #expect(Fmt.relative(threeDaysAgo, locale: Locale(identifier: "en_US")).contains("ago"))
        #expect(Fmt.relative(threeDaysAgo, locale: Locale(identifier: "pt_PT")).contains("há"))
    }

    @Test func bytes() {
        #expect(Fmt.bytes(1_500_000).contains("1,5") || Fmt.bytes(1_500_000).contains("1.5"))
        #expect(Fmt.bytes(1_500_000).contains("MB"))
    }
}

@Suite("Shell")
struct ShellTests {
    static let nasty = [
        "simple", "with spaces", "single'quote", "''", "\"double\"", "$HOME", "`whoami`", "$(rm -rf /)",
        "a;b && c | d", "new\nline", "back\\slash", "*?[]", "~", "-rf", "ç ã é 🍃",
    ]

    @Test("quote: the shell receives the text exactly as it is", arguments: nasty)
    func quoteRoundTrip(_ s: String) {
        let r = Shell.runSync("/bin/sh", ["-c", "printf %s " + Shell.quote(s)])
        #expect(r.ok)
        #expect(r.out == s)
    }

    @Test("appleScriptEscape escapes quotes and backslashes")
    func appleScriptEscape() {
        #expect(Shell.appleScriptEscape(#"a"b\c"#) == #"a\"b\\c"#)
    }

    @Test("runSync returns output, error and exit code")
    func runSync() {
        let ok = Shell.runSync("/bin/echo", ["héllo"])
        #expect(ok.ok && ok.out == "héllo\n")
        let fail = Shell.runSync("/bin/sh", ["-c", "echo error >&2; exit 3"])
        #expect(fail.status == 3 && fail.err == "error\n" && !fail.ok)
        let missing = Shell.runSync("/does/not/exist")
        #expect(missing.status == -1)
    }

    @Test("run with environment variables")
    func runWithEnv() async {
        let r = await Shell.run("/bin/sh", ["-c", "printf %s \"$PRUNE_TEST\""], env: ["PRUNE_TEST": "value"])
        #expect(r.out == "value")
    }
}

@Suite("Small functions")
struct MiscTests {
    @Test func launchItemProgram() {
        #expect(LaunchItemParser.program(of: ["Program": "/a"]) == "/a")
        #expect(LaunchItemParser.program(of: ["ProgramArguments": ["/b", "-x"]]) == "/b")
        #expect(LaunchItemParser.program(of: ["Program": "/a", "ProgramArguments": ["/b"]]) == "/a")
        #expect(LaunchItemParser.program(of: ["ProgramArguments": [String]()]) == nil)
        #expect(LaunchItemParser.program(of: [:]) == nil)
    }

    @Test func vendor() {
        #expect(AppScanner.vendor(from: "com.adobe.Photoshop") == "Adobe")
        #expect(AppScanner.vendor(from: "noDots") == "noDots")
    }

    @Test func expandHome() {
        #expect(AppScanner.expand("~/Library/Caches") == URL.home("Library/Caches"))
        #expect(AppScanner.expand("/Library/Caches").path == "/Library/Caches")
    }

    @Test("App leftover locations are folders that can never be deleted entirely")
    func leftoverLocationsAreProtectedRoots() {
        for loc in AppScanner.leftoverLocations where loc.hasPrefix("~/Library/") && !loc.contains("Internet Plug-Ins") && !loc.contains("Application Scripts") && !loc.contains("ByHost") {
            #expect(!SafetyGuard.canDelete(AppScanner.expand(loc)), "\(loc)")
        }
    }

    @Test func settingsIgnored() {
        let s = AppSettings.shared
        let saved = s.ignoredPaths
        defer { s.ignoredPaths = saved }
        s.ignoredPaths = ["/a/b"]
        #expect(s.isIgnored("/a/b"))
        #expect(s.isIgnored("/a/b/c"))
        #expect(!s.isIgnored("/a/bc"))
        #expect(!s.isIgnored("/a"))
    }

    @Test func deleteModes() {
        #expect(DeleteMode(rawValue: "trash") == .trash)
        #expect(DeleteMode(rawValue: "permanent") == .permanent)
        #expect(DeleteMode.allCases.count == 2)
    }
}
