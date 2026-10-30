import Foundation
import Testing
@testable import Prune

/// The rules that decide what each scan offers to delete and what it preselects (risk R1).
/// Each test builds a fake home in a temporary folder and points the scanners at it (ScanRoot).
func inFakeHome<T>(_ tmp: TempDir, _ body: () throws -> T) rethrows -> T {
    try ScanRoot.$home.withValue(tmp.url) { try body() }
}

func names(_ items: [CleanItem]) -> Set<String> { Set(items.map(\.url.lastPathComponent)) }
func selected(_ items: [CleanItem]) -> Set<String> { Set(items.filter(\.selected).map(\.url.lastPathComponent)) }

func plist(_ dict: [String: Any]) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
}

@Suite("System Junk rules")
struct SystemJunkTests {
    @Test("User caches skip the system's own caches and those covered by other categories")
    func userCachesExclusions() throws {
        let tmp = try TempDir()
        for name in ["com.vendor.app", "CloudKit", "com.apple.bird", "Prune", "Homebrew", "pip", "com.apple.dt.Xcode", "GeoServices"] {
            try tmp.file("Library/Caches/\(name)/blob", bytes: 100, fill: 1)
        }
        try tmp.file("Library/Caches/.DS_Store", bytes: 10, fill: 0)
        let cat = inFakeHome(tmp) { SystemJunkScanner.userCaches(running: []) }
        #expect(names(cat.items) == ["com.vendor.app"])
        #expect(selected(cat.items) == ["com.vendor.app"])
    }

    @Test("Caches of open apps are listed but not selected, whatever the case")
    func runningAppsNotSelected() throws {
        let tmp = try TempDir()
        try tmp.file("Library/Caches/com.vendor.Open/blob", bytes: 100, fill: 1)
        try tmp.file("Library/Caches/com.vendor.closed/blob", bytes: 100, fill: 1)
        let cat = inFakeHome(tmp) { SystemJunkScanner.userCaches(running: ["COM.VENDOR.OPEN"]) }
        #expect(names(cat.items) == ["com.vendor.Open", "com.vendor.closed"])
        #expect(selected(cat.items) == ["com.vendor.closed"])
        #expect(cat.items.first { !$0.selected }?.detail != nil)
    }

    @Test("Empty caches are not offered")
    func emptyNotOffered() throws {
        let tmp = try TempDir()
        try tmp.dir("Library/Caches/com.vendor.empty")
        let cat = inFakeHome(tmp) { SystemJunkScanner.userCaches(running: []) }
        #expect(cat.items.isEmpty)
    }

    @Test("Xcode: build data selected, archives listed but never selected")
    func xcode() throws {
        let tmp = try TempDir()
        try tmp.file("Library/Developer/Xcode/DerivedData/App-abc/Build/x.o", bytes: 500, fill: 2)
        try tmp.file("Library/Developer/Xcode/iOS DeviceSupport/17.0/Symbols/s", bytes: 500, fill: 2)
        try tmp.file("Library/Developer/Xcode/Archives/2026-10-01/App.xcarchive/Info.plist", bytes: 500, fill: 2)
        let cat = inFakeHome(tmp) { SystemJunkScanner.xcodeJunk() }
        #expect(names(cat.items) == ["DerivedData", "17.0", "2026-10-01"])
        #expect(selected(cat.items) == ["DerivedData", "17.0"])
    }

    @Test("Developer caches: package caches selected, Maven, NuGet and Hugging Face not")
    func devCaches() throws {
        let tmp = try TempDir()
        for path in [".npm/_cacache", ".m2/repository", ".nuget/packages", ".cache/huggingface", ".gradle/caches"] {
            try tmp.file("\(path)/x", bytes: 300, fill: 3)
        }
        let cat = inFakeHome(tmp) { SystemJunkScanner.devCaches() }
        let byName = Dictionary(uniqueKeysWithValues: cat.items.map { ($0.name, $0.selected) })
        #expect(byName == ["npm": true, "Gradle": true, "Maven": false, "NuGet": false, "Hugging Face": false])
    }

    @Test("iPhone backups are never selected and are named after the device")
    func iosBackups() throws {
        let tmp = try TempDir()
        try tmp.file("Library/iTunes/iPhone Software Updates/iPhone.ipsw", bytes: 400, fill: 4)
        try tmp.file("Library/Application Support/MobileSync/Backup/00008-ABC/Info.plist",
                     try plist(["Device Name": "Ana's iPhone"]))
        let cat = inFakeHome(tmp) { SystemJunkScanner.iosFiles() }
        #expect(selected(cat.items) == ["iPhone.ipsw"])
        let backup = try #require(cat.items.first { $0.url.lastPathComponent == "00008-ABC" })
        #expect(!backup.selected)
        #expect(backup.name.contains("Ana's iPhone"))
        #expect(cat.warning != nil)
    }

    @Test("A device name with format characters is shown as is")
    func backupNameFormatCharacters() throws {
        let tmp = try TempDir()
        try tmp.file("Library/Application Support/MobileSync/Backup/X/Info.plist", try plist(["Device Name": "%@ %n %d"]))
        let cat = inFakeHome(tmp) { SystemJunkScanner.iosFiles() }
        #expect(cat.items.first?.name.contains("%@ %n %d") == true)
    }

    @Test("Without backups there is no warning")
    func noBackupNoWarning() throws {
        let tmp = try TempDir()
        let cat = inFakeHome(tmp) { SystemJunkScanner.iosFiles() }
        #expect(cat.items.isEmpty && cat.warning == nil)
    }

    @Test("Broken preferences: empty and corrupted .plist only")
    func brokenPreferences() throws {
        let tmp = try TempDir()
        try tmp.file("Library/Preferences/good.plist", try plist(["a": 1]))
        try tmp.file("Library/Preferences/empty.plist", Data())
        try tmp.file("Library/Preferences/garbage.plist", "not a plist {{{")
        try tmp.file("Library/Preferences/ByHost/host.broken.plist", Data([0xFF, 0x00, 0x13]))
        try tmp.file("Library/Preferences/notes.txt", "")
        let cat = inFakeHome(tmp) { SystemJunkScanner.brokenPreferences() }
        #expect(names(cat.items) == ["empty.plist", "garbage.plist", "host.broken.plist"])
        #expect(cat.items.allSatisfy { $0.size >= 4096 })
    }

    @Test("Broken login items: only agents whose absolute program is gone")
    func brokenLaunchAgents() throws {
        let tmp = try TempDir()
        let present = try tmp.file("bin/tool", "#!/bin/sh")
        let agents = "Library/LaunchAgents"
        try tmp.file("\(agents)/gone.plist", try plist(["Label": "gone", "Program": tmp.path("bin/missing").path]))
        try tmp.file("\(agents)/gone-args.plist", try plist(["Label": "ga", "ProgramArguments": [tmp.path("nope").path, "-x"]]))
        try tmp.file("\(agents)/present.plist", try plist(["Label": "p", "Program": present.path]))
        try tmp.file("\(agents)/system.plist", try plist(["Label": "s", "Program": "/usr/bin/does-not-exist"]))
        try tmp.file("\(agents)/relative.plist", try plist(["Label": "r", "Program": "tool"]))
        try tmp.file("\(agents)/unreadable.plist", "<<<")
        let cat = inFakeHome(tmp) { SystemJunkScanner.brokenLaunchAgents() }
        #expect(names(cat.items) == ["gone.plist", "gone-args.plist", "unreadable.plist"])
        // Only the agent's .plist is offered, never the program it points at.
        #expect(cat.items.allSatisfy { $0.url.deletingLastPathComponent().lastPathComponent == "LaunchAgents" })
    }

    @Test("Incomplete downloads by extension, any case; finished files stay")
    func partialDownloads() throws {
        let tmp = try TempDir()
        for name in ["movie.CRDOWNLOAD", "a.part", "b.download", "c.opdownload", "report.pdf", "archive.zip"] {
            try tmp.file("Downloads/\(name)", bytes: 50, fill: 5)
        }
        let cat = inFakeHome(tmp) { SystemJunkScanner.downloadsJunk() }
        #expect(names(cat.items) == ["movie.CRDOWNLOAD", "a.part", "b.download", "c.opdownload"])
    }
}

@Suite("Trash and Mail rules")
struct TrashMailTests {
    @Test("User Trash lists its items")
    func userTrash() async throws {
        let tmp = try TempDir()
        try tmp.file(".Trash/old.txt", bytes: 10, fill: 1)
        try tmp.file(".Trash/.DS_Store", bytes: 10, fill: 1)
        let cats = await ScanRoot.$home.withValue(tmp.url) { await TrashScanner.scan(.silent) }
        #expect(names(cats[0].items) == ["old.txt"])
    }

    @Test("Volume Trash: only this user's folder, never the startup disk")
    func volumeTrashes() throws {
        let tmp = try TempDir()
        try tmp.file("Volumes/USB/.Trashes/501/photo.jpg", bytes: 10, fill: 1)
        try tmp.file("Volumes/USB/.Trashes/502/other-user.jpg", bytes: 10, fill: 1)
        try tmp.dir("Volumes/Empty/.Trashes/501")
        try tmp.symlink("Volumes/Macintosh HD", to: URL(fileURLWithPath: "/"))
        let cats = TrashScanner.volumeTrashes(in: tmp.path("Volumes"), uid: 501)
        #expect(cats.count == 1)
        #expect(names(cats[0].items) == ["photo.jpg"])
    }

    @Test("Opened attachments are selected; attachments inside messages are not")
    func mail() async throws {
        let tmp = try TempDir()
        try tmp.file("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/ABC/invoice.pdf", bytes: 20, fill: 1)
        try tmp.file("Library/Mail/V10/acct/INBOX.mbox/X/Data/1/Attachments/42/2/photo.jpg", bytes: 30, fill: 1)
        try tmp.file("Library/Mail/V10/acct/INBOX.mbox/X/Data/1/Messages/42.emlx", bytes: 30, fill: 1)
        try tmp.file("Library/Mail/MailData/Attachments/x/ignored.bin", bytes: 30, fill: 1)
        let cats = await ScanRoot.$home.withValue(tmp.url) { await MailAttachmentsScanner.scan(.silent) }
        let downloads = try #require(cats.first { $0.id == "mailDownloads" })
        let inMessages = try #require(cats.first { $0.id == "mailAttachments" })
        #expect(selected(downloads.items) == ["ABC"])
        #expect(names(inMessages.items) == ["photo.jpg"])
        #expect(selected(inMessages.items).isEmpty)
    }
}

@Suite("Privacy rules")
struct PrivacyTests {
    @Test("Safari: history and cookies selected; top sites, local storage and website data not")
    func safari() throws {
        let tmp = try TempDir()
        for f in ["History.db", "History.db-wal", "TopSites.plist", "Bookmarks.plist", "LocalStorage/x"] {
            try tmp.file("Library/Safari/\(f)", bytes: 10, fill: 1)
        }
        try tmp.file("Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies", bytes: 10, fill: 1)
        let cat = try #require(inFakeHome(tmp) { PrivacyScanner.safari() })
        #expect(names(cat.items) == ["History.db", "History.db-wal", "TopSites.plist", "LocalStorage", "Cookies"])
        #expect(selected(cat.items) == ["History.db", "History.db-wal", "Cookies"])
        // Bookmarks are never offered.
        #expect(!names(cat.items).contains("Bookmarks.plist"))
    }

    @Test("Chromium: every real profile, without passwords or bookmarks")
    func chromiumProfiles() throws {
        let tmp = try TempDir()
        let base = "Library/Application Support/Google/Chrome"
        for profile in ["Default", "Profile 1", "Guest Profile", "System Profile"] {
            for f in ["History", "Cookies", "Web Data", "Login Data", "Bookmarks", "Cache/data_0"] {
                try tmp.file("\(base)/\(profile)/\(f)", bytes: 10, fill: 1)
            }
        }
        let chrome = try #require(PrivacyScanner.chromiumBrowsers.first { $0.name == "Google Chrome" })
        let cat = try #require(inFakeHome(tmp) { PrivacyScanner.chromium(chrome) })
        let profiles = Set(cat.items.map { $0.url.pathComponents.dropLast().last! }).union(
            cat.items.filter { $0.name == "Cache" }.map { $0.url.deletingLastPathComponent().lastPathComponent })
        #expect(profiles == ["Default", "Profile 1", "Guest Profile"])
        #expect(!names(cat.items).contains("Login Data") && !names(cat.items).contains("Bookmarks"))
        #expect(cat.items.filter { $0.url.lastPathComponent == "Web Data" }.allSatisfy { !$0.selected })
        // With more than one profile, each item says which one it is from.
        #expect(cat.items.filter { $0.url.lastPathComponent == "History" }.allSatisfy { $0.detail?.contains("(") == true })
    }

    @Test("A browser with no data is not listed")
    func chromiumMissing() throws {
        let tmp = try TempDir()
        let edge = try #require(PrivacyScanner.chromiumBrowsers.first { $0.name == "Microsoft Edge" })
        #expect(inFakeHome(tmp) { PrivacyScanner.chromium(edge) } == nil)
    }

    @Test("Every browser whose data is cleaned is closed first")
    func browsersToClose() {
        let ids = PrivacyScanner.browserBundleIDs
        #expect(ids["com.apple.Safari"] == "Safari" && ids["org.mozilla.firefox"] == "Firefox")
        for b in PrivacyScanner.chromiumBrowsers { #expect(ids[b.bundleID] == b.name) }
    }

    @Test("Firefox: clearing history keeps bookmarks and annotated pages")
    func firefoxKeepsBookmarks() async throws {
        let tmp = try TempDir()
        let profile = try tmp.dir("Library/Application Support/Firefox/Profiles/abc.default")
        let places = profile.appendingPathComponent("places.sqlite")
        try sqlite(places, """
            CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT);
            CREATE TABLE moz_historyvisits (id INTEGER PRIMARY KEY, place_id INTEGER);
            CREATE TABLE moz_inputhistory (place_id INTEGER, input TEXT);
            CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, fk INTEGER);
            CREATE TABLE moz_annos (id INTEGER PRIMARY KEY, place_id INTEGER);
            INSERT INTO moz_places VALUES (1, 'https://bookmarked'), (2, 'https://visited'), (3, 'https://annotated');
            INSERT INTO moz_historyvisits (place_id) VALUES (1), (2), (2), (3);
            INSERT INTO moz_inputhistory VALUES (2, 'vis');
            INSERT INTO moz_bookmarks (fk) VALUES (1), (NULL);
            INSERT INTO moz_annos (place_id) VALUES (3);
            """)
        try tmp.file("Library/Application Support/Firefox/Profiles/abc.default/cookies.sqlite", bytes: 10, fill: 1)
        try tmp.file("Library/Application Support/Firefox/Profiles/abc.default/logins.json", bytes: 10, fill: 1)
        let cat = try #require(inFakeHome(tmp) { PrivacyScanner.firefox() })
        #expect(!names(cat.items).contains("logins.json"))
        let history = try #require(cat.items.first { $0.url.lastPathComponent == "places.sqlite" })
        let report = await Cleaner.remove([history], mode: .permanent)
        #expect(report.removed == 1)
        #expect(exists(places))
        #expect(try sqlite(places, "SELECT group_concat(id) FROM (SELECT id FROM moz_places ORDER BY id);") == "1,3")
        #expect(try sqlite(places, "SELECT count(*) FROM moz_historyvisits;") == "0")
        #expect(try sqlite(places, "SELECT count(*) FROM moz_inputhistory;") == "0")
        #expect(try sqlite(places, "SELECT count(*) FROM moz_bookmarks;") == "2")
    }

    @Test("Recent items: only the known lists")
    func recentItems() throws {
        let tmp = try TempDir()
        let sfl = "Library/Application Support/com.apple.sharedfilelist"
        try tmp.file("\(sfl)/com.apple.LSSharedFileList.RecentDocuments.sfl3", bytes: 10, fill: 1)
        try tmp.file("\(sfl)/com.apple.LSSharedFileList.FavoriteItems.sfl3", bytes: 10, fill: 1)
        let cat = inFakeHome(tmp) { PrivacyScanner.recentItems() }
        #expect(names(cat.items).contains("com.apple.LSSharedFileList.RecentDocuments.sfl3"))
        #expect(!names(cat.items).contains("com.apple.LSSharedFileList.FavoriteItems.sfl3"))
    }
}

/// Runs SQL with the system's sqlite3 and returns its output.
@discardableResult
func sqlite(_ db: URL, _ sql: String) throws -> String {
    let r = Shell.runSync("/usr/bin/sqlite3", [db.path, sql])
    guard r.ok else { throw CocoaError(.fileReadUnknown) }
    return r.out.trimmingCharacters(in: .whitespacesAndNewlines)
}

@Suite("Uninstaller rules")
struct UninstallerRulesTests {
    static let zebra = AppInfo(url: URL(fileURLWithPath: "/Applications/Zebra Tool.app"), name: "Zebra Tool", bundleID: "com.zebracorp.zebratool",
                               version: "1", build: "1", size: 0, lastUsed: nil, isAppStore: false, vendor: "Zebracorp", feedURL: nil)

    @Test("Leftovers: files named after the app or its bundle ID, in every support folder")
    func leftovers() throws {
        let tmp = try TempDir()
        for path in ["Library/Application Support/Zebra Tool/db", "Library/Caches/com.zebracorp.zebratool/c",
                     "Library/Preferences/com.zebracorp.zebratool.plist", "Library/Containers/com.zebracorp.zebratool/x",
                     "Library/Saved Application State/com.zebracorp.zebratool.savedState/s",
                     "Library/Group Containers/ABCDE12345.com.zebracorp.zebratool/g",
                     "Library/Preferences/com.zebracorp.zebratoolkit.plist", "Library/Caches/com.zebracorp/c",
                     "Library/Application Support/Zebra/other", "Library/Application Support/Zebra Toolbox/x"] {
            try tmp.file(path, bytes: 10, fill: 1)
        }
        let items = inFakeHome(tmp) { AppScanner.leftovers(for: Self.zebra) }
        #expect(names(items) == ["Zebra Tool", "com.zebracorp.zebratool", "com.zebracorp.zebratool.plist",
                                 "com.zebracorp.zebratool.savedState", "ABCDE12345.com.zebracorp.zebratool"])
        #expect(items.allSatisfy { $0.selected })
    }

    @Test("Short app names never match by name")
    func shortNames() throws {
        let tmp = try TempDir()
        try tmp.file("Library/Application Support/Zed/x", bytes: 10, fill: 1)
        let zed = AppInfo(url: URL(fileURLWithPath: "/Applications/Zed.app"), name: "Zed", bundleID: "dev.zedcorp.zed-xyz",
                          version: "", build: "", size: 0, lastUsed: nil, isAppStore: false, vendor: "", feedURL: nil)
        let items = inFakeHome(tmp) { AppScanner.leftovers(for: zed) }
        #expect(items.isEmpty)
    }

    @Test("Orphans: bundle-ID folders of removed apps, never selected; system, groups and installed vendors stay")
    func orphans() throws {
        let tmp = try TempDir()
        for path in ["Library/Application Support/com.goneapp.editor/x", "Library/Preferences/com.goneapp.editor.plist",
                     "Library/Application Support/com.apple.something/x", "Library/Application Support/group.com.x.y/x",
                     "Library/Application Support/com.installed.app/x", "Library/Application Support/com.installed.other/x",
                     "Library/Caches/com.maker.app-helper/x", "Library/Application Support/Some Folder/x",
                     "Library/Application Support/notanid/x"] {
            try tmp.file(path, bytes: 10, fill: 1)
        }
        let items = inFakeHome(tmp) { AppScanner.orphans(installedIDs: ["com.installed.app", "com.maker.app"]) }
        #expect(names(items) == ["com.goneapp.editor", "com.goneapp.editor.plist"])
        #expect(items.allSatisfy { !$0.selected })
    }

    @Test("Vendor from the bundle ID")
    func vendor() {
        #expect(AppScanner.vendor(from: "com.zebracorp.tool") == "Zebracorp")
        #expect(AppScanner.vendor(from: "single") == "single")
    }
}
