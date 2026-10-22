import Foundation
import Testing
@testable import Prune

/// A proteção de pastas é a última barreira antes de apagar: cada caminho crítico tem de ficar bloqueado.
@Suite("SafetyGuard")
struct SafetyGuardTests {
    static let criticalExact = [
        "/", "/System", "/Library", "/Applications", "/Users", "/usr", "/bin", "/sbin", "/etc", "/var",
        "/private", "/private/var", "/private/etc", "/private/tmp", "/tmp", "/Volumes", "/opt", "/dev",
        "/Library/Caches", "/Library/LaunchDaemons", "/Users/Shared", "/Applications/Utilities",
    ]

    static let criticalHome = [
        "", "Library", "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Applications",
        ".Trash", "Library/Caches", "Library/Application Support", "Library/Preferences", "Library/Containers",
        "Library/Mail", "Library/Safari", "Library/Keychains", "Library/Mobile Documents", "Library/CloudStorage",
    ]

    static let criticalInside = [
        "/System/Library/CoreServices/Finder.app", "/usr/bin/ls", "/usr/lib/libSystem.B.dylib", "/bin/zsh",
        "/sbin/mount", "/private/var/db/receipts", "/Library/Apple/System",
    ]

    @Test("Bloqueia pastas críticas do sistema", arguments: criticalExact)
    func blocksSystemFolders(_ path: String) {
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: path)))
    }

    @Test("Bloqueia pastas pessoais", arguments: criticalHome)
    func blocksHomeFolders(_ sub: String) {
        let url = sub.isEmpty ? home : home.appendingPathComponent(sub)
        #expect(!SafetyGuard.canDelete(url))
    }

    @Test("Bloqueia o conteúdo das zonas do sistema", arguments: criticalInside)
    func blocksInsideProtectedPrefixes(_ path: String) {
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: path)))
    }

    @Test("Bloqueia o porta-chaves e o iCloud Drive por inteiro")
    func blocksKeychainsAndICloud() {
        #expect(!SafetyGuard.canDelete(.home("Library/Keychains/login.keychain-db")))
        #expect(!SafetyGuard.canDelete(.home("Library/Mobile Documents/com~apple~CloudDocs/Documento.pages")))
    }

    @Test("Resolve /var, /tmp e /etc para /private")
    func resolvesSymlinkedParents() {
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: "/var/db/teste")))
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: "/etc")))
    }

    @Test("Normaliza caminhos com '..', '.' e barras a mais")
    func normalizesPaths() {
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: "/Applications/../System")))
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: "/System/./")))
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: home.path + "/Documents/")))
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: home.path + "/Library/Caches/../Preferences")))
    }

    @Test("Bloqueia a própria app")
    func blocksOwnBundle() {
        #expect(!SafetyGuard.canDelete(Bundle.main.bundleURL))
    }

    @Test("Permite ficheiros comuns dentro de pastas do utilizador")
    func allowsOrdinaryFiles() throws {
        let tmp = try TempDir()
        let f = try tmp.file("lixo.log", "x")
        #expect(SafetyGuard.canDelete(f))
        #expect(SafetyGuard.canDelete(tmp.url))
        #expect(SafetyGuard.canDelete(.home("Library/Caches/com.exemplo.app")))
        #expect(SafetyGuard.canDelete(.home("Downloads/instalador.dmg")))
    }

    @Test("Apagar uma ligação simbólica não é bloqueado pelo destino")
    func symlinkItselfIsJudgedByItsOwnPath() throws {
        let tmp = try TempDir()
        let link = try tmp.symlink("para-sistema", to: URL(fileURLWithPath: "/System"))
        #expect(SafetyGuard.canDelete(link))
    }

    @Test("Respeita as pastas ignoradas nas Definições (e as subpastas)")
    func respectsIgnoredPaths() throws {
        let tmp = try TempDir()
        let inner = try tmp.file("sub/ficheiro.txt", "x")
        let settings = AppSettings.shared
        let saved = settings.ignoredPaths
        defer { settings.ignoredPaths = saved }

        // O caminho ignorado é guardado tal como resolvido (/private/var/…), por isso testamos ambos.
        let resolved = tmp.url.resolvingSymlinksInPath().path
        settings.ignoredPaths = [tmp.url.path, resolved]
        #expect(!SafetyGuard.canDelete(tmp.url))
        #expect(!SafetyGuard.canDelete(inner))

        // Um nome que só começa da mesma forma não fica ignorado.
        settings.ignoredPaths = [tmp.url.path + "/su", resolved + "/su"]
        #expect(SafetyGuard.canDelete(inner))
    }
}
