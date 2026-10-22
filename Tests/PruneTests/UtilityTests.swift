import Foundation
import Testing
@testable import Prune

@Suite("Versões")
struct VersionTests {
    @Test("Comparação numérica", arguments: [
        ("1.10.2", "1.9", true), ("2.0", "2.0.0", false), ("1.2", "1.10", false), ("1.2.5", "1.2.4", true),
        ("1.2.4", "1.2.5", false), ("10", "9.9.9", true), ("v2.1", "2.0", true), ("1.0 (45)", "1.0 (44)", true),
        ("", "1.0", false), ("1.0", "", false), ("beta", "1.0", false), ("1.0.1", "1.0", true),
    ])
    func isNewer(_ a: String, _ b: String, _ expected: Bool) {
        #expect(Version.isNewer(a, than: b) == expected)
    }

    @Test("Nunca é mais nova do que ela própria")
    func irreflexive() {
        for v in ["1", "1.2", "1.2.3", "0.0.1"] { #expect(!Version.isNewer(v, than: v)) }
    }

    @Test func numbers() {
        #expect(Version.numbers("1.2.3-beta4") == [1, 2, 3, 4])
        #expect(Version.numbers("abc").isEmpty)
    }
}

@Suite("Formatação")
struct FormattingTests {
    @Test("Plurais", arguments: [(0, "0 itens"), (1, "1 item"), (2, "2 itens"), (1000, "1000 itens")])
    func count(_ n: Int, _ expected: String) {
        #expect(Fmt.count(n, "item", "itens") == expected)
    }

    @Test func percent() {
        #expect(Fmt.percent(0) == "0%")
        #expect(Fmt.percent(0.426) == "43%")
        #expect(Fmt.percent(1) == "100%")
    }

    @Test func emptyDates() {
        #expect(Fmt.date(nil) == "—")
        #expect(Fmt.relative(nil) == "nunca")
        #expect(!Fmt.date(Date()).isEmpty)
    }

    @Test func bytes() {
        #expect(Fmt.bytes(1_500_000).contains("1,5") || Fmt.bytes(1_500_000).contains("1.5"))
        #expect(Fmt.bytes(1_500_000).contains("MB"))
    }
}

@Suite("Shell")
struct ShellTests {
    static let nasty = [
        "simples", "com espaços", "aspa'simples", "''", "\"duplas\"", "$HOME", "`whoami`", "$(rm -rf /)",
        "a;b && c | d", "nova\nlinha", "barra\\invertida", "*?[]", "~", "-rf", "ç ã é 🍃",
    ]

    @Test("quote: o shell recebe o texto exatamente como está", arguments: nasty)
    func quoteRoundTrip(_ s: String) {
        let r = Shell.runSync("/bin/sh", ["-c", "printf %s " + Shell.quote(s)])
        #expect(r.ok)
        #expect(r.out == s)
    }

    @Test("appleScriptEscape escapa aspas e barras")
    func appleScriptEscape() {
        #expect(Shell.appleScriptEscape(#"a"b\c"#) == #"a\"b\\c"#)
    }

    @Test("runSync devolve saída, erro e código de saída")
    func runSync() {
        let ok = Shell.runSync("/bin/echo", ["olá"])
        #expect(ok.ok && ok.out == "olá\n")
        let fail = Shell.runSync("/bin/sh", ["-c", "echo erro >&2; exit 3"])
        #expect(fail.status == 3 && fail.err == "erro\n" && !fail.ok)
        let missing = Shell.runSync("/nao/existe")
        #expect(missing.status == -1)
    }

    @Test("run com variáveis de ambiente")
    func runWithEnv() async {
        let r = await Shell.run("/bin/sh", ["-c", "printf %s \"$PRUNE_TESTE\""], env: ["PRUNE_TESTE": "valor"])
        #expect(r.out == "valor")
    }
}

@Suite("Pequenas funções")
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
        #expect(AppScanner.vendor(from: "semPontos") == "semPontos")
    }

    @Test func expandHome() {
        #expect(AppScanner.expand("~/Library/Caches") == URL.home("Library/Caches"))
        #expect(AppScanner.expand("/Library/Caches").path == "/Library/Caches")
    }

    @Test("Os sítios de restos de apps são pastas, nunca podem ser apagados por inteiro")
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
