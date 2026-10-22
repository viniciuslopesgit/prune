import Foundation
import Testing
@testable import Prune

/// Only `.permanent` mode is tested: `.trash` would touch the user's real Trash.
@Suite("Cleanup")
struct CleanerTests {
    @Test("Deletes files and folders")
    func removesFilesAndFolders() throws {
        let tmp = try TempDir()
        let f = try tmp.file("cache.db", "x")
        try tmp.file("folder/a/b/c.txt", "y")

        #expect(Cleaner.removeSync(f, mode: .permanent))
        #expect(Cleaner.removeSync(tmp.path("folder"), mode: .permanent))
        #expect(!exists(f))
        #expect(!exists(tmp.path("folder")))
    }

    @Test("Refuses protected paths and does not touch them")
    func refusesProtected() {
        for p in ["/System", "/Applications", home.path, home.path + "/Library"] {
            let u = URL(fileURLWithPath: p)
            #expect(!Cleaner.removeSync(u, mode: .permanent))
            #expect(u.exists)
        }
    }

    @Test("An item that no longer exists counts as cleaned")
    func missingCountsAsRemoved() throws {
        let tmp = try TempDir()
        #expect(Cleaner.removeSync(tmp.path("already-gone"), mode: .permanent))
    }

    @Test("Removes broken links")
    func removesBrokenSymlink() throws {
        let tmp = try TempDir()
        let link = try tmp.symlink("broken", to: tmp.path("does-not-exist"))
        #expect(Cleaner.removeSync(link, mode: .permanent))
        #expect(!exists(link))
    }

    @Test("Deleting a link to a folder does not delete the folder")
    func symlinkToFolderKeepsTarget() throws {
        let tmp = try TempDir()
        try tmp.file("real/important.txt", "stays")
        let link = try tmp.symlink("link", to: tmp.path("real"))

        #expect(Cleaner.removeSync(link, mode: .permanent))
        #expect(!exists(link))
        #expect(read(tmp.path("real/important.txt")) == "stays")
    }

    @Test("Folder with partially protected contents: deletes what it can and reports failure")
    func partiallyProtectedFolder() throws {
        let tmp = try TempDir()
        try tmp.file("p/loose.txt", "x")
        try tmp.file("p/locked/stuck.txt", "y")
        let locked = tmp.path("p/locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        #expect(!Cleaner.removeSync(tmp.path("p"), mode: .permanent))
        #expect(!exists(tmp.path("p/loose.txt")))
        #expect(exists(tmp.path("p/locked/stuck.txt")))
    }

    @Test("The report adds up the space freed and lists the failures")
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

    @Test("Removal by URL measures the space before deleting")
    func reportFromURLs() async throws {
        let tmp = try TempDir()
        let a = try tmp.file("a", bytes: 50_000, fill: 2)
        let r = await Cleaner.remove(urls: [a, URL(fileURLWithPath: "/usr/bin/ls")], mode: .permanent)
        #expect(r.removed == 1)
        #expect(r.freed >= 50_000)
        #expect(r.failed.map(\.path) == ["/usr/bin/ls"])
    }

    @Test("Administrator: protected paths never reach the script")
    func retryAsAdminFiltersProtected() async {
        // Only protected paths: returns right away, without asking for the password.
        let urls = [URL(fileURLWithPath: "/System"), home]
        let r = await Cleaner.retryAsAdmin(urls, mode: .permanent)
        #expect(r.removed == 0)
        #expect(r.failed == urls)
    }
}

@Suite("Categories and reports")
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
        #expect(!c.allSelected, "an empty category does not count as fully selected")
        #expect(c.noneSelected)
    }

    @Test func itemDefaultsToFileName() {
        let i = CleanItem(url: URL(fileURLWithPath: "/a/b/name.log"), size: 1)
        #expect(i.name == "name.log")
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
