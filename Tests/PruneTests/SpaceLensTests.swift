import Foundation
import Testing
@testable import Prune

@Suite("Lente de Espaço")
struct SpaceScannerTests {
    func scan(_ url: URL) -> DiskNode { SpaceScanner(progress: .silent).scan(url) }

    @Test("Tamanho de cada pasta = soma dos filhos; filhos do maior para o menor")
    func treeSizes() throws {
        let tmp = try TempDir()
        try tmp.file("grande/a", bytes: 2_000_000, fill: 1)
        try tmp.file("grande/b", bytes: 1_000_000, fill: 1)
        try tmp.file("pequeno", bytes: 10_000, fill: 1)
        try tmp.dir("vazia")

        let root = scan(tmp.url)
        #expect(root.url == tmp.url)
        #expect(root.size == root.children.reduce(0) { $0 + $1.size })
        #expect(root.children.map(\.name) == ["grande", "pequeno", "vazia"])
        let grande = root.children[0]
        #expect(grande.isDirectory)
        #expect(grande.size == FS.size(of: tmp.path("grande")))
        #expect(grande.children.map(\.name) == ["a", "b"])
        #expect(grande.children[0].url.path == tmp.path("grande/a").path)
        #expect(grande.children[0].path.map(\.name) == [tmp.url.lastPathComponent, "grande", "a"])
    }

    @Test("Ignora ligações simbólicas (não conta nada duas vezes)")
    func skipsSymlinks() throws {
        let tmp = try TempDir()
        try tmp.file("real", bytes: 100_000, fill: 1)
        try tmp.symlink("ligacao", to: tmp.path("real"))
        try tmp.symlink("ciclo", to: tmp.url)
        let root = scan(tmp.url)
        #expect(root.children.map(\.name) == ["real"])
    }

    @Test("Pastas pequenas ficam sem detalhe")
    func smallFoldersHaveNoChildren() throws {
        let tmp = try TempDir()
        try tmp.file("p/a", bytes: 1000, fill: 1)
        let p = try #require(scan(tmp.url).children.first)
        #expect(p.size > 0)
        #expect(p.children.isEmpty)
    }

    @Test("Mais de 50 itens: os mais pequenos são agregados num só nó")
    func aggregatesSmallItems() throws {
        let tmp = try TempDir()
        for i in 0..<60 { try tmp.file("f\(i)", bytes: (i + 1) * 4096, fill: 1) }
        let root = scan(tmp.url)
        #expect(root.children.count == SpaceScanner.maxChildren + 1)
        let agg = try #require(root.children.last)
        #expect(agg.isAggregate)
        #expect(agg.name == "10 itens mais pequenos")
        #expect(agg.url == tmp.url, "o nó agregado não aponta para nenhum ficheiro")
        #expect(root.size == root.children.reduce(0) { $0 + $1.size })
        #expect(!root.children.dropLast().contains { $0.isAggregate })
    }
}

@Suite("Treemap")
struct TreemapTests {
    static let cases: [[Double]] = [
        [6, 6, 4, 3, 2, 2, 1], [1], [5, 5], [100, 1, 1, 1], (1...80).map(Double.init), [3, 0, 2],
    ]

    @Test("Ocupa a área toda, sem sair do retângulo e proporcional ao tamanho", arguments: cases)
    func fillsRect(sizes: [Double]) {
        let frame = CGRect(x: 10, y: 20, width: 600, height: 400)
        let rects = Treemap.layout(sizes: sizes, in: frame)
        #expect(rects.count == sizes.count)
        let area = rects.reduce(0.0) { $0 + Double($1.width * $1.height) }
        #expect(abs(area - 240_000) < 0.5)
        let total = sizes.reduce(0, +)
        for (r, s) in zip(rects, sizes) {
            #expect(r.minX >= frame.minX - 0.001 && r.maxX <= frame.maxX + 0.001)
            #expect(r.minY >= frame.minY - 0.001 && r.maxY <= frame.maxY + 0.001)
            #expect(abs(Double(r.width * r.height) - s / total * 240_000) < 0.5)
        }
    }

    @Test("Os retângulos não se sobrepõem")
    func noOverlap() {
        let rects = Treemap.layout(sizes: [9, 7, 5, 4, 3, 2, 2, 1, 1], in: CGRect(x: 0, y: 0, width: 300, height: 500))
        for i in rects.indices {
            for j in rects.indices where j > i {
                let o = rects[i].intersection(rects[j])
                #expect(o.isNull || o.width * o.height < 0.01)
            }
        }
    }

    @Test("Casos degenerados devolvem retângulos vazios")
    func degenerate() {
        #expect(Treemap.layout(sizes: [], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
        #expect(Treemap.layout(sizes: [0, 0], in: CGRect(x: 0, y: 0, width: 10, height: 10)) == [.zero, .zero])
        #expect(Treemap.layout(sizes: [1, 2], in: .zero) == [.zero, .zero])
    }
}
