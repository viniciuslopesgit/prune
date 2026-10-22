import Foundation
import Testing
@testable import Prune

/// Folder protection is the last barrier before deleting: every critical path must be blocked.
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

    @Test("Blocks critical system folders", arguments: criticalExact)
    func blocksSystemFolders(_ path: String) {
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: path)))
    }

    @Test("Blocks personal folders", arguments: criticalHome)
    func blocksHomeFolders(_ sub: String) {
        let url = sub.isEmpty ? home : home.appendingPathComponent(sub)
        #expect(!SafetyGuard.canDelete(url))
    }

    @Test("Blocks the contents of system areas", arguments: criticalInside)
    func blocksInsideProtectedPrefixes(_ path: String) {
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: path)))
    }

    @Test("Blocks the keychain and iCloud Drive entirely")
    func blocksKeychainsAndICloud() {
        #expect(!SafetyGuard.canDelete(.home("Library/Keychains/login.keychain-db")))
        #expect(!SafetyGuard.canDelete(.home("Library/Mobile Documents/com~apple~CloudDocs/Document.pages")))
    }

    @Test("Resolves /var, /tmp and /etc to /private")
    func resolvesSymlinkedParents() {
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: "/var/db/test")))
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: "/etc")))
    }

    @Test("Normalizes paths with '..', '.' and extra slashes")
    func normalizesPaths() {
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: "/Applications/../System")))
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: "/System/./")))
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: home.path + "/Documents/")))
        #expect(!SafetyGuard.canDelete(URL(fileURLWithPath: home.path + "/Library/Caches/../Preferences")))
    }

    @Test("Blocks the app itself")
    func blocksOwnBundle() {
        #expect(!SafetyGuard.canDelete(Bundle.main.bundleURL))
    }

    @Test("Allows ordinary files inside user folders")
    func allowsOrdinaryFiles() throws {
        let tmp = try TempDir()
        let f = try tmp.file("junk.log", "x")
        #expect(SafetyGuard.canDelete(f))
        #expect(SafetyGuard.canDelete(tmp.url))
        #expect(SafetyGuard.canDelete(.home("Library/Caches/com.example.app")))
        #expect(SafetyGuard.canDelete(.home("Downloads/installer.dmg")))
    }

    @Test("Deleting a symbolic link is not blocked by its target")
    func symlinkItselfIsJudgedByItsOwnPath() throws {
        let tmp = try TempDir()
        let link = try tmp.symlink("to-system", to: URL(fileURLWithPath: "/System"))
        #expect(SafetyGuard.canDelete(link))
    }

    @Test("Respects the folders ignored in Settings (and their subfolders)")
    func respectsIgnoredPaths() throws {
        let tmp = try TempDir()
        let inner = try tmp.file("sub/file.txt", "x")
        let settings = AppSettings.shared
        let saved = settings.ignoredPaths
        defer { settings.ignoredPaths = saved }

        // The ignored path is stored as resolved (/private/var/…), so both are tested.
        let resolved = tmp.url.resolvingSymlinksInPath().path
        settings.ignoredPaths = [tmp.url.path, resolved]
        #expect(!SafetyGuard.canDelete(tmp.url))
        #expect(!SafetyGuard.canDelete(inner))

        // A name that only starts the same way is not ignored.
        settings.ignoredPaths = [tmp.url.path + "/su", resolved + "/su"]
        #expect(SafetyGuard.canDelete(inner))
    }
}
