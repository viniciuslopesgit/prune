import Foundation
import Testing
@testable import Prune

@Suite("Destruidor")
struct ShredderTests {
    @Test("Destrói um ficheiro e os dados deixam de existir no disco", arguments: [0, 1, 4096, 1_048_576, 2_621_441])
    func shredsFileAndItsData(size: Int) throws {
        let tmp = try TempDir()
        let f = try tmp.file("segredo.bin", noise(size, seed: 1))
        // Uma ligação física partilha os dados: se o ficheiro só fosse desligado, o conteúdo ficava aqui.
        let hard = tmp.path("ligacao-fisica")
        try FileManager.default.linkItem(at: f, to: hard)

        #expect(Shredder.shredSync(f, passes: 1))
        #expect(!exists(f))
        let left = try Data(contentsOf: hard)
        #expect(left.isEmpty, "o conteúdo original continua no disco")
    }

    @Test("Várias passagens", arguments: [0, 1, 3, 7])
    func multiplePasses(passes: Int) throws {
        let tmp = try TempDir()
        let f = try tmp.file("a.bin", bytes: 300_000, fill: 0xAB)
        #expect(Shredder.shredSync(f, passes: passes))
        #expect(!exists(f))
    }

    @Test("Não deixa o nome original na pasta")
    func renamesBeforeDeleting() throws {
        let tmp = try TempDir()
        let f = try tmp.file("nome-revelador.txt", "x")
        #expect(Shredder.shredSync(f, passes: 1))
        #expect(FS.children(tmp.url).isEmpty)
    }

    @Test("Destrói pastas com subpastas")
    func shredsFolders() throws {
        let tmp = try TempDir()
        let folder = try tmp.dir("pasta")
        let a = try tmp.file("pasta/a.txt", "a")
        try tmp.file("pasta/sub/b.txt", "b")
        let hard = tmp.path("copia-a")
        try FileManager.default.linkItem(at: a, to: hard)

        #expect(Shredder.shredSync(folder, passes: 1))
        #expect(!exists(folder))
        #expect(try Data(contentsOf: hard).isEmpty)
    }

    @Test("Uma ligação simbólica dentro da pasta nunca sobrescreve o ficheiro de fora")
    func symlinkInsideFolderKeepsTarget() throws {
        let tmp = try TempDir()
        let target = try tmp.file("original.txt", "conteúdo original")
        try tmp.dir("a-destruir")
        try tmp.symlink("a-destruir/ligacao", to: target)

        _ = Shredder.shredSync(tmp.path("a-destruir"), passes: 3)
        #expect(!exists(tmp.path("a-destruir")))
        #expect(read(target) == "conteúdo original")
    }

    @Test("Destruir uma ligação simbólica só remove a ligação")
    func shreddingSymlinkRemovesOnlyLink() throws {
        let tmp = try TempDir()
        let target = try tmp.file("original.txt", "intacto")
        let link = try tmp.symlink("ligacao", to: target)

        #expect(Shredder.shredSync(link, passes: 1))
        #expect(!exists(link))
        #expect(read(target) == "intacto")
    }

    @Test("Uma ligação para uma pasta não destrói o conteúdo da pasta")
    func symlinkToFolderKeepsFolder() throws {
        let tmp = try TempDir()
        try tmp.file("real/dentro.txt", "fica")
        let link = try tmp.symlink("ligacao", to: tmp.path("real"))

        #expect(Shredder.shredSync(link, passes: 1))
        #expect(read(tmp.path("real/dentro.txt")) == "fica")
    }

    @Test("Recusa caminhos protegidos")
    func refusesProtectedPaths() {
        #expect(!Shredder.shredSync(URL(fileURLWithPath: "/System"), passes: 1))
        #expect(!Shredder.shredSync(home, passes: 1))
        #expect(!Shredder.shredSync(.home("Documents"), passes: 1))
    }

    @Test("Ficheiro inexistente devolve falha, sem fechar a app")
    func missingFileFails() throws {
        let tmp = try TempDir()
        #expect(!Shredder.shredSync(tmp.path("nao-existe"), passes: 1))
    }

    @Test("Ficheiro só de leitura devolve falha e fica intacto")
    func readOnlyFileFails() throws {
        let tmp = try TempDir()
        let f = try tmp.file("bloqueado.txt", "protegido")
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: f.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: f.path) }

        #expect(!Shredder.shredSync(f, passes: 1))
        #expect(read(f) == "protegido")
    }

    @Test("Versão assíncrona")
    func asyncShred() async throws {
        let tmp = try TempDir()
        let f = try tmp.file("a.txt", "x")
        #expect(await Shredder.shred(f, passes: 2))
        #expect(!exists(f))
    }
}
