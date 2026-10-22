import Foundation
import Testing
@testable import Prune

@Suite("Shredder")
struct ShredderTests {
    @Test("Shreds a file and its data no longer exists on disk", arguments: [0, 1, 4096, 1_048_576, 2_621_441])
    func shredsFileAndItsData(size: Int) throws {
        let tmp = try TempDir()
        let f = try tmp.file("secret.bin", noise(size, seed: 1))
        // A hard link shares the data: if the file were only unlinked, the contents would stay here.
        let hard = tmp.path("hard-link")
        try FileManager.default.linkItem(at: f, to: hard)

        #expect(Shredder.shredSync(f, passes: 1))
        #expect(!exists(f))
        let left = try Data(contentsOf: hard)
        #expect(left.isEmpty, "the original contents are still on disk")
    }

    @Test("Several passes", arguments: [0, 1, 3, 7])
    func multiplePasses(passes: Int) throws {
        let tmp = try TempDir()
        let f = try tmp.file("a.bin", bytes: 300_000, fill: 0xAB)
        #expect(Shredder.shredSync(f, passes: passes))
        #expect(!exists(f))
    }

    @Test("Does not leave the original name in the folder")
    func renamesBeforeDeleting() throws {
        let tmp = try TempDir()
        let f = try tmp.file("revealing-name.txt", "x")
        #expect(Shredder.shredSync(f, passes: 1))
        #expect(FS.children(tmp.url).isEmpty)
    }

    @Test("Shreds folders with subfolders")
    func shredsFolders() throws {
        let tmp = try TempDir()
        let folder = try tmp.dir("folder")
        let a = try tmp.file("folder/a.txt", "a")
        try tmp.file("folder/sub/b.txt", "b")
        let hard = tmp.path("copy-a")
        try FileManager.default.linkItem(at: a, to: hard)

        #expect(Shredder.shredSync(folder, passes: 1))
        #expect(!exists(folder))
        #expect(try Data(contentsOf: hard).isEmpty)
    }

    @Test("A symbolic link inside the folder never overwrites the file outside")
    func symlinkInsideFolderKeepsTarget() throws {
        let tmp = try TempDir()
        let target = try tmp.file("original.txt", "original content")
        try tmp.dir("to-shred")
        try tmp.symlink("to-shred/link", to: target)

        _ = Shredder.shredSync(tmp.path("to-shred"), passes: 3)
        #expect(!exists(tmp.path("to-shred")))
        #expect(read(target) == "original content")
    }

    @Test("Shredding a symbolic link only removes the link")
    func shreddingSymlinkRemovesOnlyLink() throws {
        let tmp = try TempDir()
        let target = try tmp.file("original.txt", "intact")
        let link = try tmp.symlink("link", to: target)

        #expect(Shredder.shredSync(link, passes: 1))
        #expect(!exists(link))
        #expect(read(target) == "intact")
    }

    @Test("A link to a folder does not shred the folder's contents")
    func symlinkToFolderKeepsFolder() throws {
        let tmp = try TempDir()
        try tmp.file("real/inside.txt", "stays")
        let link = try tmp.symlink("link", to: tmp.path("real"))

        #expect(Shredder.shredSync(link, passes: 1))
        #expect(read(tmp.path("real/inside.txt")) == "stays")
    }

    @Test("Refuses protected paths")
    func refusesProtectedPaths() {
        #expect(!Shredder.shredSync(URL(fileURLWithPath: "/System"), passes: 1))
        #expect(!Shredder.shredSync(home, passes: 1))
        #expect(!Shredder.shredSync(.home("Documents"), passes: 1))
    }

    @Test("A missing file returns failure, without crashing the app")
    func missingFileFails() throws {
        let tmp = try TempDir()
        #expect(!Shredder.shredSync(tmp.path("does-not-exist"), passes: 1))
    }

    @Test("A read-only file returns failure and stays intact")
    func readOnlyFileFails() throws {
        let tmp = try TempDir()
        let f = try tmp.file("locked.txt", "protected")
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: f.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: f.path) }

        #expect(!Shredder.shredSync(f, passes: 1))
        #expect(read(f) == "protected")
    }

    @Test("Async version")
    func asyncShred() async throws {
        let tmp = try TempDir()
        let f = try tmp.file("a.txt", "x")
        #expect(await Shredder.shred(f, passes: 2))
        #expect(!exists(f))
    }
}
