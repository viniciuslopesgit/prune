import Foundation
import Testing
@testable import Prune

@Suite("Files")
struct FileSystemTests {
    @Test("On-disk size of files and folders")
    func sizes() throws {
        let tmp = try TempDir()
        let a = try tmp.file("p/a", bytes: 100_000, fill: 1)
        let b = try tmp.file("p/sub/b", bytes: 50_000, fill: 2)
        let sa = FS.size(of: a), sb = FS.size(of: b)
        #expect(sa >= 100_000)
        #expect(sb >= 50_000)
        #expect(FS.size(of: tmp.path("p")) == sa + sb)
        #expect(FS.size(of: tmp.path("does-not-exist")) == 0)
        #expect(FS.sizes(of: [a, b, tmp.path("does-not-exist")]) == [sa, sb, 0])
    }

    @Test("Symbolic links do not count (nor are they followed)")
    func symlinksHaveNoSize() throws {
        let tmp = try TempDir()
        let big = try tmp.file("big", bytes: 200_000, fill: 1)
        try tmp.dir("p")
        let link = try tmp.symlink("p/link", to: big)
        #expect(FS.size(of: link) == 0)
        try tmp.symlink("p/folder", to: tmp.url)
        #expect(FS.size(of: tmp.path("p")) == 0)
    }

    @Test("childItems skips .DS_Store, exclusions and items below the minimum; sorts by size")
    func childItems() throws {
        let tmp = try TempDir()
        try tmp.file("d/.DS_Store", bytes: 9000, fill: 0)
        try tmp.file("d/.localized", "")
        try tmp.file("d/small", bytes: 10, fill: 1)
        try tmp.file("d/big", bytes: 90_000, fill: 1)
        try tmp.file("d/medium", bytes: 20_000, fill: 1)
        try tmp.file("d/Keep-This", bytes: 50_000, fill: 1)

        let items = FS.childItems(of: tmp.path("d"), selected: false, excluding: ["keep"], minSize: 5000, detail: "note")
        #expect(items.map(\.name) == ["big", "medium"])
        #expect(items.allSatisfy { !$0.selected && $0.detail == "note" })
    }

    @Test("childItems with olderThan only includes what has not been touched since")
    func childItemsOlderThan() throws {
        let tmp = try TempDir()
        let old = try tmp.file("d/old", "x")
        try tmp.file("d/recent", "x")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-86_400 * 30)], ofItemAtPath: old.path)
        let items = FS.childItems(of: tmp.path("d"), olderThan: Date().addingTimeInterval(-86_400 * 7))
        #expect(items.map(\.name) == ["old"])
    }

    @Test("item(_:) only exists for non-empty, unprotected folders")
    func singleItem() throws {
        let tmp = try TempDir()
        try tmp.file("full/x", "x")
        try tmp.dir("empty")
        #expect(FS.item(tmp.path("full"), name: "Full")?.name == "Full")
        #expect(FS.item(tmp.path("empty")) == nil)
        #expect(FS.item(tmp.path("does-not-exist")) == nil)
        #expect(FS.item(URL(fileURLWithPath: "/System")) == nil)
    }

    @Test("forEach walks everything and stops when the body returns false")
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

    @Test("displayPath abbreviates the home folder")
    func displayPath() {
        #expect(URL.home("Downloads/a.zip").displayPath == "~/Downloads/a.zip")
        #expect(URL(fileURLWithPath: "/Library/Caches").displayPath == "/Library/Caches")
    }

    @Test("URL.isDirectory and exists")
    func urlHelpers() throws {
        let tmp = try TempDir()
        let f = try tmp.file("f", "x")
        #expect(tmp.url.isDirectory)
        #expect(!f.isDirectory)
        #expect(f.exists)
        #expect(!tmp.path("no").exists)
    }
}
