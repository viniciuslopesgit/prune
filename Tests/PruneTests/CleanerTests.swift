import Foundation
import Testing
@testable import Prune

/// Só o modo `.permanent` é testado: `.trash` mexeria no Lixo verdadeiro do utilizador.
@Suite("Limpeza")
struct CleanerTests {
    @Test("Apaga ficheiros e pastas")
    func removesFilesAndFolders() throws {
        let tmp = try TempDir()
        let f = try tmp.file("cache.db", "x")
        try tmp.file("pasta/a/b/c.txt", "y")

        #expect(Cleaner.removeSync(f, mode: .permanent))
        #expect(Cleaner.removeSync(tmp.path("pasta"), mode: .permanent))
        #expect(!exists(f))
        #expect(!exists(tmp.path("pasta")))
    }

    @Test("Recusa caminhos protegidos e não toca neles")
    func refusesProtected() {
        for p in ["/System", "/Applications", home.path, home.path + "/Library"] {
            let u = URL(fileURLWithPath: p)
            #expect(!Cleaner.removeSync(u, mode: .permanent))
            #expect(u.exists)
        }
    }

    @Test("Um item que já não existe conta como limpo")
    func missingCountsAsRemoved() throws {
        let tmp = try TempDir()
        #expect(Cleaner.removeSync(tmp.path("ja-foi"), mode: .permanent))
    }

    @Test("Remove ligações partidas")
    func removesBrokenSymlink() throws {
        let tmp = try TempDir()
        let link = try tmp.symlink("partida", to: tmp.path("nao-existe"))
        #expect(Cleaner.removeSync(link, mode: .permanent))
        #expect(!exists(link))
    }

    @Test("Apagar uma ligação para uma pasta não apaga a pasta")
    func symlinkToFolderKeepsTarget() throws {
        let tmp = try TempDir()
        try tmp.file("real/importante.txt", "fica")
        let link = try tmp.symlink("ligacao", to: tmp.path("real"))

        #expect(Cleaner.removeSync(link, mode: .permanent))
        #expect(!exists(link))
        #expect(read(tmp.path("real/importante.txt")) == "fica")
    }

    @Test("Pasta com conteúdo parcialmente protegido: apaga o possível e reporta falha")
    func partiallyProtectedFolder() throws {
        let tmp = try TempDir()
        try tmp.file("p/solto.txt", "x")
        try tmp.file("p/fechada/preso.txt", "y")
        let locked = tmp.path("p/fechada")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        #expect(!Cleaner.removeSync(tmp.path("p"), mode: .permanent))
        #expect(!exists(tmp.path("p/solto.txt")))
        #expect(exists(tmp.path("p/fechada/preso.txt")))
    }

    @Test("O relatório soma o espaço libertado e lista as falhas")
    func reportFromItems() async throws {
        let tmp = try TempDir()
        let a = try tmp.file("a", bytes: 10, fill: 1)
        let items = [
            CleanItem(url: a, size: 100),
            CleanItem(url: URL(fileURLWithPath: "/System"), size: 999),
            CleanItem(url: tmp.path("x"), size: 7, customAction: { true }),
            CleanItem(url: tmp.path("y"), size: 5, customAction: { false }),
        ]
        let r = await Cleaner.remove(items, mode: .permanent)
        #expect(r.removed == 2)
        #expect(r.freed == 107)
        #expect(r.failed == [URL(fileURLWithPath: "/System"), tmp.path("y")])
        #expect(!exists(a))
    }

    @Test("Remoção por URL mede o espaço antes de apagar")
    func reportFromURLs() async throws {
        let tmp = try TempDir()
        let a = try tmp.file("a", bytes: 50_000, fill: 2)
        let r = await Cleaner.remove(urls: [a, URL(fileURLWithPath: "/usr/bin/ls")], mode: .permanent)
        #expect(r.removed == 1)
        #expect(r.freed >= 50_000)
        #expect(r.failed.map(\.path) == ["/usr/bin/ls"])
    }

    @Test("Administrador: caminhos protegidos nunca chegam ao script")
    func retryAsAdminFiltersProtected() async {
        // Só caminhos protegidos: devolve logo, sem pedir a palavra-passe.
        let urls = [URL(fileURLWithPath: "/System"), home]
        let r = await Cleaner.retryAsAdmin(urls, mode: .permanent)
        #expect(r.removed == 0)
        #expect(r.failed == urls)
    }
}

@Suite("Categorias e relatórios")
struct CleanModelTests {
    func item(_ size: Int64, _ selected: Bool) -> CleanItem {
        CleanItem(url: URL(fileURLWithPath: "/tmp/\(UUID().uuidString)"), size: size, selected: selected)
    }

    @Test func categoryTotals() {
        let c = CleanCategory(id: "c", name: "C", icon: "", info: "", items: [item(10, true), item(20, false), item(30, true)])
        #expect(c.totalSize == 60)
        #expect(c.selectedSize == 40)
        #expect(c.selectedCount == 2)
        #expect(!c.allSelected)
        #expect(!c.noneSelected)
    }

    @Test func emptyCategory() {
        let c = CleanCategory(id: "c", name: "C", icon: "", info: "", items: [])
        #expect(c.totalSize == 0)
        #expect(!c.allSelected, "uma categoria vazia não conta como toda selecionada")
        #expect(c.noneSelected)
    }

    @Test func itemDefaultsToFileName() {
        let i = CleanItem(url: URL(fileURLWithPath: "/a/b/nome.log"), size: 1)
        #expect(i.name == "nome.log")
        #expect(i.selected)
    }

    @Test func reportMerge() {
        var a = CleanReport(freed: 10, removed: 1, failed: [URL(fileURLWithPath: "/x")])
        a.merge(CleanReport(freed: 5, removed: 2, failed: [URL(fileURLWithPath: "/y")]))
        #expect(a.freed == 15)
        #expect(a.removed == 3)
        #expect(a.failed.map(\.path) == ["/x", "/y"])
    }
}
