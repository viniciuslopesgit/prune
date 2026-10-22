import AppKit

struct LoginItem: Identifiable {
    var id: String { name }
    let name: String
    let path: String
}

struct LaunchItem: Identifiable {
    enum Domain: String { case userAgent = "Utilizador", globalAgent = "Global", daemon = "Sistema" }
    var id: String { url.path }
    let url: URL
    let label: String
    let program: String?
    let domain: Domain
    var loaded: Bool
    var disabled: Bool
    var programMissing: Bool
    var ownerName: String
}

struct ProcessInfoRow: Identifiable {
    var id: Int32 { pid }
    let pid: Int32
    let cpu: Double
    let memory: Int64
    let name: String
    let user: String
    var icon: NSImage?
    var isApp: Bool
}

enum OptimizationService {
    static func loginItems() async -> [LoginItem] {
        let script = """
        tell application "System Events"
            set out to ""
            repeat with li in login items
                set out to out & (name of li) & "|||" & (path of li) & linefeed
            end repeat
            return out
        end tell
        """
        let r = await Shell.osascript(script)
        return r.out.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: "|||")
            guard parts.count == 2, !parts[0].isEmpty else { return nil }
            return LoginItem(name: parts[0], path: parts[1])
        }
    }

    static func removeLoginItem(_ item: LoginItem) async -> Bool {
        await Shell.osascript("tell application \"System Events\" to delete login item \"\(Shell.appleScriptEscape(item.name))\"").ok
    }

    static func launchItems() async -> [LaunchItem] {
        let uid = Shell.uid
        async let listOut = Shell.run("/bin/launchctl", ["list"])
        async let disabledUser = Shell.run("/bin/launchctl", ["print-disabled", "gui/\(uid)"])
        async let disabledSystem = Shell.run("/bin/launchctl", ["print-disabled", "system"])
        let (list, du, ds) = await (listOut, disabledUser, disabledSystem)
        let loaded = Set(list.out.split(separator: "\n").compactMap { $0.split(separator: "\t").last.map(String.init) })
        let userDisabled = parseDisabled(du.out)
        let systemDisabled = parseDisabled(ds.out)

        var items: [LaunchItem] = []
        let dirs: [(URL, LaunchItem.Domain)] = [
            (URL.home("Library/LaunchAgents"), .userAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .globalAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .daemon),
        ]
        for (dir, domain) in dirs {
            for plist in FS.children(dir) where plist.pathExtension == "plist" {
                let dict = NSDictionary(contentsOf: plist) as? [String: Any] ?? [:]
                let label = dict["Label"] as? String ?? plist.deletingPathExtension().lastPathComponent
                let program = LaunchItemParser.program(of: dict)
                let missing = program.map { $0.hasPrefix("/") && !FileManager.default.fileExists(atPath: $0) } ?? false
                let isLoaded: Bool
                if domain == .daemon {
                    isLoaded = await Shell.run("/bin/launchctl", ["print", "system/\(label)"]).ok
                } else {
                    isLoaded = loaded.contains(label)
                }
                let disabled = domain == .daemon ? systemDisabled.contains(label) : userDisabled.contains(label)
                items.append(LaunchItem(
                    url: plist, label: label, program: program, domain: domain, loaded: isLoaded,
                    disabled: disabled, programMissing: missing, ownerName: ownerName(label: label, program: program)
                ))
            }
        }
        return items.sorted { $0.ownerName.localizedCaseInsensitiveCompare($1.ownerName) == .orderedAscending }
    }

    private static func parseDisabled(_ out: String) -> Set<String> {
        var s = Set<String>()
        for line in out.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("\""), t.hasSuffix("disabled") || t.hasSuffix("true") else { continue }
            if let end = t.dropFirst().firstIndex(of: "\"") {
                s.insert(String(t[t.index(after: t.startIndex)..<end]))
            }
        }
        return s
    }

    /// Nome legível: tenta encontrar a app a que o programa pertence.
    static func ownerName(label: String, program: String?) -> String {
        if let program, let range = program.range(of: ".app/") {
            return URL(fileURLWithPath: String(program[..<range.lowerBound]) + ".app").deletingPathExtension().lastPathComponent
        }
        let parts = label.split(separator: ".")
        if parts.count >= 2 { return String(parts[1]).capitalized }
        return label
    }

    static func setEnabled(_ item: LaunchItem, enabled: Bool) async -> Bool {
        let uid = Shell.uid
        switch item.domain {
        case .userAgent, .globalAgent:
            let target = "gui/\(uid)/\(item.label)"
            if enabled {
                _ = await Shell.run("/bin/launchctl", ["enable", target])
                _ = await Shell.run("/bin/launchctl", ["bootstrap", "gui/\(uid)", item.url.path])
            } else {
                _ = await Shell.run("/bin/launchctl", ["bootout", "gui/\(uid)", item.url.path])
                _ = await Shell.run("/bin/launchctl", ["disable", target])
            }
            return true
        case .daemon:
            let path = Shell.quote(item.url.path)
            let label = Shell.quote("system/\(item.label)")
            let script = enabled
                ? "launchctl enable \(label); launchctl bootstrap system \(path)"
                : "launchctl bootout system \(path); launchctl disable \(label)"
            return await Shell.admin(script).ok
        }
    }

    static func remove(_ item: LaunchItem) async -> Bool {
        guard SafetyGuard.canDelete(item.url) else { return false }
        if item.domain == .userAgent {
            _ = await Shell.run("/bin/launchctl", ["bootout", "gui/\(Shell.uid)", item.url.path])
            return Cleaner.removeSync(item.url, mode: .trash)
        }
        let domain = item.domain == .daemon ? "system" : "gui/\(Shell.uid)"
        let r = await Shell.admin("launchctl bootout \(domain) \(Shell.quote(item.url.path)) 2>/dev/null; rm -f \(Shell.quote(item.url.path))")
        return r.ok
    }

    static func processes() async -> [ProcessInfoRow] {
        let r = await Shell.run("/bin/ps", ["-Aco", "pid=,pcpu=,rss=,user=,comm="])
        let me = NSUserName()
        let apps = Dictionary(NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        return r.out.split(separator: "\n").compactMap { line -> ProcessInfoRow? in
            let f = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard f.count == 5, let pid = Int32(f[0]), let cpu = Double(f[1].replacingOccurrences(of: ",", with: ".")), let rss = Int64(f[2]) else { return nil }
            let user = String(f[3])
            let app = apps[pid]
            return ProcessInfoRow(
                pid: pid, cpu: cpu, memory: rss * 1024, name: app?.localizedName ?? String(f[4]), user: user,
                icon: app?.icon, isApp: app?.activationPolicy == .regular && user == me
            )
        }
    }
}
