import Foundation

/// Stops the app from deleting critical system or user folders.
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
        return Set(s.map(key))
    }()

    private static let protectedPrefixes: [String] = [
        "/System/", "/usr/bin/", "/usr/sbin/", "/usr/lib/", "/usr/libexec/", "/usr/share/", "/bin/",
        "/sbin/", "/private/var/db/", "/Library/Apple/", home.path + "/Library/Keychains/",
        home.path + "/Library/Mobile Documents/",
    ].map(key)

    /// APFS and HFS+ volumes are case-insensitive by default and accept any Unicode normalization:
    /// "/SYSTEM" or "~/documents" are the same folder as "/System" and "~/Documents". Paths are
    /// compared in this form, so a spelling variant cannot get past the list.
    static func key(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func canDelete(_ url: URL) -> Bool {
        let standard = url.standardizedFileURL
        let path = standard.path
        guard !path.isEmpty else { return false }
        // Checks the path as requested and with the parent folder resolved (/var, /tmp and /etc are
        // links to /private/…). The last component is not resolved: deleting a link does not touch its target.
        // Both come from the standardized URL: the original's last component can be "." or ".."
        // ("/private/var/db/." would otherwise be checked as "/private/var/.").
        let parent = standard.deletingLastPathComponent().path
        let resolved = URL(fileURLWithPath: realPath(parent) ?? parent).appendingPathComponent(standard.lastPathComponent).path
        return [path, resolved].allSatisfy(isAllowed)
    }

    /// `realpath(3)`: unlike `resolvingSymlinksInPath()`, keeps the /private prefix.
    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func isAllowed(_ path: String) -> Bool {
        let k = key(path)
        if protectedExact.contains(k) { return false }
        // A prefix protects its contents and the folder itself ("/private/var/db" as well as "/private/var/db/x").
        if protectedPrefixes.contains(where: { k.hasPrefix($0) || k + "/" == $0 }) { return false }
        let bundle = key(Bundle.main.bundlePath)
        if k == bundle || k.hasPrefix(bundle + "/") { return false }
        return !AppSettings.shared.isIgnored(path)
    }
}
