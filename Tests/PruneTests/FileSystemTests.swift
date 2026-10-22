import Foundation
import Testing
@testable import Prune

@Suite("Ficheiros")
struct FileSystemTests {
    @Test("Tamanho em disco de ficheiros e pastas")
    func sizes() throws {
        let tmp = try TempDir()
        let a = try tmp.file("p/a", bytes: 100_000, fill: 1)
        let b = try tmp.file("p/sub/b", bytes: 50_000, fill: 2)
        let sa = FS.size(of: a), sb = FS.size(of: b)
        #expect(sa >= 100_000)
        #expect(sb >= 50_000)
        #expect(FS.size(of: tmp.path("p")) == sa + sb)
        #expect(FS.size(of: tmp.path("nao-existe")) == 0)
        #expect(FS.sizes(of: [a, b, tmp.path("nao-existe")]) == [sa, sb, 0])
    }

    @Test("Ligações simbólicas não contam (nem seguem para o destino)")
    func symlinksHaveNoSize() throws {
        let tmp = try TempDir()
        let big = try tmp.file("grande", bytes: 200_000, fill: 1)
        try tmp.dir("p")
        let link = try tmp.symlink("p/ligacao", to: big)
        #expect(FS.size(of: link) == 0)
        try tmp.symlink("p/pasta", to: tmp.url)
        #expect(FS.size(of: tmp.path("p")) == 0)
    }

    @Test("childItems ignora .DS_Store, exclusões e itens abaixo do mínimo; ordena por tamanho")
    func childItems() throws {
        let tmp = try TempDir()
        try tmp.file("d/.DS_Store", bytes: 9000, fill: 0)
        try tmp.file("d/.localized", "")
        try tmp.file("d/pequeno", bytes: 10, fill: 1)
        try tmp.file("d/grande", bytes: 90_000, fill: 1)
        try tmp.file("d/medio", bytes: 20_000, fill: 1)
        try tmp.file("d/Manter-Isto", bytes: 50_000, fill: 1)

        let items = FS.childItems(of: tmp.path("d"), selected: false, excluding: ["manter"], minSize: 5000, detail: "nota")
        #expect(items.map(\.name) == ["grande", "medio"])
        #expect(items.allSatisfy { !$0.selected && $0.detail == "nota" })
    }

    @Test("childItems com olderThan só inclui o que não foi mexido desde então")
    func childItemsOlderThan() throws {
        let tmp = try TempDir()
        let old = try tmp.file("d/antigo", "x")
        try tmp.file("d/recente", "x")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-86_400 * 30)], ofItemAtPath: old.path)
        let items = FS.childItems(of: tmp.path("d"), olderThan: Date().addingTimeInterval(-86_400 * 7))
        #expect(items.map(\.name) == ["antigo"])
    }

    @Test("item(_:) só existe para pastas não vazias e não protegidas")
    func singleItem() throws {
        let tmp = try TempDir()
        try tmp.file("cheia/x", "x")
        try tmp.dir("vazia")
        #expect(FS.item(tmp.path("cheia"), name: "Cheia")?.name == "Cheia")
        #expect(FS.item(tmp.path("vazia")) == nil)
        #expect(FS.item(tmp.path("nao-existe")) == nil)
        #expect(FS.item(URL(fileURLWithPath: "/System")) == nil)
    }

    @Test("forEach percorre tudo e para quando o corpo devolve false")
    func forEachStops() throws {
        let tmp = try TempDir()
        for i in 0..<600 { try tmp.file("f\(i)", "") }
        func count(limit: Int) -> Int {
            var n = 0
            let e = FileManager.default.enumerator(at: tmp.url, includingPropertiesForKeys: nil)!
            FS.forEach(e, batch: 64) { _ in n += 1; return n < limit }
            return n
        }
        #expect(count(limit: .max) == 600)
        #expect(count(limit: 100) == 100)
    }

    @Test("displayPath abrevia a pasta pessoal")
    func displayPath() {
        #expect(URL.home("Downloads/a.zip").displayPath == "~/Downloads/a.zip")
        #expect(URL(fileURLWithPath: "/Library/Caches").displayPath == "/Library/Caches")
    }

    @Test("URL.isDirectory e exists")
    func urlHelpers() throws {
        let tmp = try TempDir()
        let f = try tmp.file("f", "x")
        #expect(tmp.url.isDirectory)
        #expect(!f.isDirectory)
        #expect(f.exists)
        #expect(!tmp.path("nao").exists)
    }
}
