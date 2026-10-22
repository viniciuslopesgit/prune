import Foundation

/// Impede que a app apague pastas críticas do sistema ou do utilizador.
enum SafetyGuard {
    private static let protectedExact: Set<String> = {
        let h = home.path
        var s: Set<String> = [
            "/", "/System", "/Library", "/Applications", "/Users", "/usr", "/bin", "/sbin", "/etc",
            "/var", "/private", "/private/var", "/private/etc", "/private/tmp", "/tmp", "/Volumes",
            "/opt", "/cores", "/dev", "/Network", "/Library/Caches", "/Library/Logs",
            "/Library/Application Support", "/Library/Preferences", "/Library/LaunchAgents",
            "/Library/LaunchDaemons", "/Users/Shared", "/Applications/Utilities",
            h,
        ]
        for sub in [
            "Library", "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Applications",
            "Public", ".Trash", "Library/Caches", "Library/Logs", "Library/Application Support",
            "Library/Preferences", "Library/Containers", "Library/Group Containers", "Library/Mail",
            "Library/LaunchAgents", "Library/Safari", "Library/Saved Application State",
            "Library/Developer", "Library/Developer/Xcode", "Library/Developer/CoreSimulator",
            "Library/Logs/DiagnosticReports", "Library/HTTPStorages", "Library/WebKit", "Library/Cookies",
            "Library/Mobile Documents", "Library/CloudStorage", "Library/Keychains",
        ] {
            s.insert(h + "/" + sub)
        }
        return s
    }()

    private static let protectedPrefixes: [String] = [
        "/System/", "/usr/bin/", "/usr/sbin/", "/usr/lib/", "/usr/libexec/", "/usr/share/", "/bin/",
        "/sbin/", "/private/var/db/", "/Library/Apple/", home.path + "/Library/Keychains/",
        home.path + "/Library/Mobile Documents/",
    ]

    static func canDelete(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        if path.isEmpty || protectedExact.contains(path) { return false }
        if protectedPrefixes.contains(where: { path.hasPrefix($0) }) { return false }
        if path.hasPrefix(Bundle.main.bundlePath) { return false }
        if AppSettings.shared.isIgnored(path) { return false }
        return true
    }
}
