import AppKit

/// Full Disk Access (needed for Safari, Mail, etc.).
enum Permissions {
    /// Locations protected only by Full Disk Access. Without the permission, reading fails
    /// with "Operation not permitted" — without showing prompts to the user (unlike
    /// Documents, Desktop or other apps' containers, which ask).
    /// Several locations, because they change between macOS versions (in macOS 27 the user's
    /// TCC folder is no longer accessible).
    static let fullDiskAccessProbes: [(path: String, isDirectory: Bool)] = [
        ("/Library/Application Support/com.apple.TCC/TCC.db", false),
        (home.path + "/Library/Application Support/com.apple.TCC/TCC.db", false),
        ("/Library/Preferences/com.apple.TimeMachine.plist", false),
        (home.path + "/Library/Safari", true),
        (home.path + "/Library/Mail", true),
        (home.path + "/Library/Messages", true),
    ]

    static var hasFullDiskAccess: Bool {
        fullDiskAccessProbes.contains { probe($0.path, isDirectory: $0.isDirectory) == .readable }
    }

    /// Checks the permission in a new process. macOS keeps the access decision for the lifetime
    /// of the process: if the app launched before the permission was granted (or even right after an
    /// update), it keeps seeing "denied" until it is reopened. A child process is evaluated afresh
    /// (with Prune's identity), so it shows the real state.
    static func hasFullDiskAccessFresh() async -> Bool {
        let files = fullDiskAccessProbes.filter { !$0.isDirectory }.map(\.path)
        let dirs = fullDiskAccessProbes.filter(\.isDirectory).map(\.path)
        let script = (files.map { "head -c 1 \(Shell.quote($0)) >/dev/null 2>&1 && exit 0" }
                      + dirs.map { "ls \(Shell.quote($0)) >/dev/null 2>&1 && exit 0" }
                      + ["exit 1"]).joined(separator: "; ")
        return await Shell.run("/bin/sh", ["-c", script]).ok
    }

    enum AccessState: Equatable {
        case granted
        /// The permission is granted, but this process does not see it yet: the app must be reopened.
        case needsRelaunch
        case denied
    }

    static func accessState() async -> AccessState {
        if hasFullDiskAccess { return .granted }
        return await hasFullDiskAccessFresh() ? .needsRelaunch : .denied
    }

    /// Reopens the app (to apply a permission that was just granted).
    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \(Shell.quote(path))"]
        try? p.run()
        NSApp.terminate(nil)
    }

    /// Logs the permission state to ~/Library/Logs/Prune/permissions.log (diagnostics).
    static func log(_ message: String) {
        let dir = home.appendingPathComponent("Library/Logs/Prune")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("permissions.log")
        let f = ISO8601DateFormatter()
        f.timeZone = .current
        let line = "\(f.string(from: Date())) pid=\(getpid()) \(message)\n"
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            try? h.close()
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    enum ProbeResult: String { case readable, denied, missing, error }

    static func probe(_ path: String, isDirectory: Bool) -> ProbeResult {
        if isDirectory {
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: path)
                return .readable
            } catch let e as NSError {
                if e.code == NSFileReadNoSuchFileError || e.code == NSFileNoSuchFileError { return .missing }
                return e.code == NSFileReadNoPermissionError ? .denied : .error
            }
        }
        let fd = open(path, O_RDONLY)
        if fd >= 0 { close(fd); return .readable }
        switch errno {
        case ENOENT: return .missing
        case EPERM, EACCES: return .denied
        default: return .error
        }
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
