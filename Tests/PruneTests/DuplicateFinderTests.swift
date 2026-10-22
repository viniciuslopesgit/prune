import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Prune

@Suite("Duplicados")
struct DuplicateFinderTests {
    func find(_ tmp: TempDir, minSize: Int64 = 1) -> [DupGroup] {
        DuplicateFinder.find(in: [tmp.url], minSize: minSize, progress: .silent)
    }

    func names(_ g: DupGroup) -> Set<String> { Set(g.files.map(\.url.lastPathComponent)) }

    @Test("SHA-256 igual ao de referência")
    func hashMatchesKnownVectors() throws {
        let tmp = try TempDir()
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: DuplicateFinder.hashChunk, alignment: 16)
        defer { buffer.deallocate() }

        let abc = try tmp.file("abc", "abc")
        #expect(DuplicateFinder.hash(abc, limit: nil, buffer: buffer) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let empty = try tmp.file("vazio", "")
        #expect(DuplicateFinder.hash(empty, limit: nil, buffer: buffer) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        // Só os primeiros 3 bytes de "abcdef" = SHA-256("abc").
        let abcdef = try tmp.file("abcdef", "abcdef")
        #expect(DuplicateFinder.hash(abcdef, limit: 3, buffer: buffer) == DuplicateFinder.hash(abc, limit: nil, buffer: buffer))
        #expect(DuplicateFinder.hash(tmp.path("nao-existe"), limit: nil, buffer: buffer) == nil)
    }

    @Test("Hash de ficheiros maiores do que o buffer")
    func hashAcrossChunks() throws {
        let tmp = try TempDir()
        let big = noise(DuplicateFinder.hashChunk * 2 + 123, seed: 7)
        let a = try tmp.file("a", big)
        let b = try tmp.file("b", big)
        var changed = big
        changed[changed.count - 1] ^= 0xFF
        let c = try tmp.file("c", changed)
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: DuplicateFinder.hashChunk, alignment: 16)
        defer { buffer.deallocate() }
        let ha = DuplicateFinder.hash(a, limit: nil, buffer: buffer)
        #expect(ha != nil)
        #expect(ha == DuplicateFinder.hash(b, limit: nil, buffer: buffer))
        #expect(ha != DuplicateFinder.hash(c, limit: nil, buffer: buffer))
    }

    @Test("Agrupa ficheiros idênticos, em pastas diferentes")
    func groupsIdentical() throws {
        let tmp = try TempDir()
        let data = noise(200_000, seed: 1)
        try tmp.file("a.bin", data)
        try tmp.file("sub/b.bin", data)
        try tmp.file("sub/fundo/c.bin", data)
        try tmp.file("unico.bin", noise(200_000, seed: 2))

        let groups = find(tmp)
        #expect(groups.count == 1)
        #expect(names(groups[0]) == ["a.bin", "b.bin", "c.bin"])
        #expect(groups[0].size == 200_000)
        #expect(groups[0].wasted == 400_000)
        #expect(!groups[0].similar)
    }

    @Test("Mesmo tamanho e mesmo início, mas fim diferente: não são duplicados")
    func samePrefixDifferentTail() throws {
        let tmp = try TempDir()
        var a = noise(300_000, seed: 3)
        try tmp.file("a", a)
        a[299_999] ^= 0x01
        try tmp.file("b", a)
        #expect(find(tmp).isEmpty)
    }

    @Test("Ficheiros pequenos (≤ 64 KB) iguais e diferentes")
    func smallFiles() throws {
        let tmp = try TempDir()
        try tmp.file("a", "igual")
        try tmp.file("b", "igual")
        try tmp.file("c", "outro")
        let groups = find(tmp)
        #expect(groups.count == 1)
        #expect(names(groups[0]) == ["a", "b"])
    }

    @Test("Respeita o tamanho mínimo")
    func minSize() throws {
        let tmp = try TempDir()
        try tmp.file("a", bytes: 1000, fill: 1)
        try tmp.file("b", bytes: 1000, fill: 1)
        #expect(find(tmp, minSize: 1001).isEmpty)
        #expect(find(tmp, minSize: 1000).count == 1)
    }

    @Test("Uma ligação simbólica não conta como cópia")
    func linksAreNotCopies() throws {
        let tmp = try TempDir()
        let a = try tmp.file("a", noise(10_000, seed: 4))
        try tmp.symlink("ligacao", to: a)
        #expect(find(tmp).isEmpty)
    }

    @Test("Ignora ficheiros ocultos")
    func skipsHidden() throws {
        let tmp = try TempDir()
        try tmp.file("a", "igual")
        try tmp.file(".b", "igual")
        #expect(find(tmp).isEmpty)
    }

    @Test("O mais antigo fica em primeiro (é o que se mantém)")
    func oldestFirst() throws {
        let tmp = try TempDir()
        let fm = FileManager.default
        let now = Date()
        for (name, age) in [("novo", 10.0), ("antigo", 100_000.0), ("medio", 1000.0)] {
            let f = try tmp.file(name, "conteúdo")
            try fm.setAttributes([.creationDate: now.addingTimeInterval(-age)], ofItemAtPath: f.path)
        }
        let g = try #require(find(tmp).first)
        #expect(g.files.map(\.url.lastPathComponent) == ["antigo", "medio", "novo"])
    }

    @Test("Grupos ordenados pelo espaço desperdiçado")
    func sortedByWaste() throws {
        let tmp = try TempDir()
        try tmp.file("p1", bytes: 100, fill: 1)
        try tmp.file("p2", bytes: 100, fill: 1)
        try tmp.file("g1", bytes: 5000, fill: 2)
        try tmp.file("g2", bytes: 5000, fill: 2)
        try tmp.file("m1", bytes: 1000, fill: 3)
        try tmp.file("m2", bytes: 1000, fill: 3)
        try tmp.file("m3", bytes: 1000, fill: 3)
        #expect(find(tmp).map(\.wasted) == [5000, 2000, 100])
    }

    @Test("Pasta vazia ou inexistente")
    func emptyRoots() throws {
        let tmp = try TempDir()
        #expect(find(tmp).isEmpty)
        #expect(DuplicateFinder.find(in: [tmp.path("nao-existe")], minSize: 1, progress: .silent).isEmpty)
    }

    /// PNG desenhado no momento: riscas horizontais (`stripes`) ou um tabuleiro de xadrez.
    func png(_ tmp: TempDir, _ name: String, checker: Bool, shift: Int = 0) throws {
        let side = 128
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for y in stride(from: 0, to: side, by: 16) {
            for x in stride(from: 0, to: side, by: 16) {
                let dark = checker ? ((x + y) / 16) % 2 == 0 : (y / 16) % 2 == 0
                ctx.setFillColor(dark ? CGColor(red: 0.1, green: 0.3, blue: 0.1, alpha: 1) : CGColor(red: 1, green: 0.9, blue: 0.2, alpha: 1))
                ctx.fill(CGRect(x: x, y: y + shift, width: 16, height: 16))
            }
        }
        let url = tmp.path(name)
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        #expect(CGImageDestinationFinalize(dest))
    }

    @Test("Fotografias semelhantes: agrupa as parecidas e deixa as diferentes de fora")
    func similarPhotos() throws {
        let tmp = try TempDir()
        try png(tmp, "riscas.png", checker: false)
        try png(tmp, "riscas-copia.png", checker: false)
        try png(tmp, "xadrez.png", checker: true)
        try tmp.file("nao-e-imagem.txt", "x")

        let r = DuplicateFinder.similarPhotos(in: [tmp.url], threshold: 0.05, progress: .silent)
        // Se o Vision não analisar as imagens, o erro aparece aqui em vez de um "nada encontrado".
        try #require(r.analysed == 3, "Vision: \(r.unreadable) imagens por analisar — \(r.firstError ?? "sem erro")")
        #expect(r.unreadable == 0)
        #expect(r.groups.count == 1)
        #expect(r.groups.first.map(names) == ["riscas.png", "riscas-copia.png"])
        #expect(r.groups.first?.similar == true)
    }

    @Test("Imagem danificada conta como não analisada, sem parar a análise")
    func unreadablePhotoIsCounted() throws {
        let tmp = try TempDir()
        try tmp.file("danificada.jpg", "isto não é uma imagem")
        let r = DuplicateFinder.similarPhotos(in: [tmp.url], threshold: 0.05, progress: .silent)
        #expect(r.unreadable == 1)
        #expect(r.analysed == 0)
        #expect(r.firstError != nil)
        #expect(r.groups.isEmpty)
    }

    @Test("Aviso ao utilizador quando há fotografias por analisar")
    func unreadableMessage() {
        #expect(DuplicatesModel.unreadableMessage(analysed: 5, unreadable: 0, error: nil) == nil)
        #expect(DuplicatesModel.unreadableMessage(analysed: 0, unreadable: 3, error: "Vision indisponível")
            == "Não foi possível analisar as fotografias neste Mac (Vision indisponível).")
        #expect(DuplicatesModel.unreadableMessage(analysed: 0, unreadable: 2, error: nil)
            == "Não foi possível analisar as fotografias neste Mac.")
        #expect(DuplicatesModel.unreadableMessage(analysed: 4, unreadable: 1, error: "x")
            == "1 fotografia não pôde ser analisada.")
        #expect(DuplicatesModel.unreadableMessage(analysed: 4, unreadable: 2, error: "x")
            == "2 fotografias não puderam ser analisadas.")
    }
}
