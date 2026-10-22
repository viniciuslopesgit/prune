import AppKit
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

/// Acesso Total ao Disco (necessário para Safari, Mail, etc.).
enum Permissions {
    /// Locais protegidos só pelo Acesso Total ao Disco. Sem a permissão, a leitura falha
    /// com "Operation not permitted" — sem mostrar pedidos ao utilizador (ao contrário de
    /// Documentos, Secretária ou contentores de outras apps, que perguntam).
    /// Vários locais, porque mudam entre versões do macOS (no macOS 27 a pasta TCC do
    /// utilizador deixou de estar acessível).
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

    /// Verifica a permissão num processo novo. O macOS guarda a decisão de acesso durante a vida
    /// do processo: se a app arrancou antes de a permissão estar ativa (ou mesmo a seguir a uma
    /// atualização), continua a ver "negado" até ser reaberta. Um processo filho é avaliado de novo
    /// (com a identidade do MaCClear), por isso mostra o estado real.
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
        /// A permissão está ativa, mas este processo ainda não a vê: é preciso reabrir a app.
        case needsRelaunch
        case denied
    }

    static func accessState() async -> AccessState {
        if hasFullDiskAccess { return .granted }
        return await hasFullDiskAccessFresh() ? .needsRelaunch : .denied
    }

    /// Reabre a app (para aplicar uma permissão acabada de conceder).
    @MainActor
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \(Shell.quote(path))"]
        try? p.run()
        NSApp.terminate(nil)
    }

    /// Regista o estado da permissão em ~/Library/Logs/MaCClear/permissoes.log (diagnóstico).
    static func log(_ message: String) {
        let dir = home.appendingPathComponent("Library/Logs/MaCClear")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("permissoes.log")
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

    enum ProbeResult: String { case readable = "legível", denied = "negado", missing = "não existe", error = "erro" }

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
