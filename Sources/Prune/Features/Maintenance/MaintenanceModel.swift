import AppKit

@MainActor
final class MaintenanceModel: ObservableObject {
    enum TaskState: Equatable { case idle, running, done, failed(String) }

    @Published var selected: Set<String> = []
    @Published var states: [String: TaskState] = [:]
    @Published var running = false
    @Published var focused: String? = MaintenanceCatalog.tasks.first?.id

    private let defaults = UserDefaults.standard

    init() {
        // By default, only tasks that do not ask for a password.
        selected = Set(recommended.filter { !$0.requiresAdmin }.map(\.id))
    }

    func lastRun(_ id: String) -> Date? { defaults.object(forKey: "maint.\(id)") as? Date }

    var recommended: [MaintenanceTask] {
        MaintenanceCatalog.tasks.filter { t in
            guard t.recommendedDays > 0 else { return false }
            guard let last = lastRun(t.id) else { return ["dns", "quicklook", "launchservices"].contains(t.id) }
            return Date().timeIntervalSince(last) > Double(t.recommendedDays) * 86400
        }
    }

    func run(_ ids: Set<String>) async {
        let tasks = MaintenanceCatalog.tasks.filter { ids.contains($0.id) }
        guard !tasks.isEmpty else { return }
        running = true
        for t in tasks { states[t.id] = .running }

        for t in tasks where !t.requiresAdmin {
            if let bundle = t.requiresClosed, !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty {
                states[t.id] = .failed(String(localized: "Quit the app first"))
                continue
            }
            let r = await Shell.zsh(t.command)
            finish(t, ok: r.ok || t.id == "dock", error: r.err)
        }

        let admin = tasks.filter(\.requiresAdmin)
        if !admin.isEmpty {
            // A single password prompt for every administrator task.
            let r = await Shell.admin(Self.adminScript(admin))
            if !r.ok && r.out.isEmpty {
                for t in admin { states[t.id] = .failed(r.err.contains("-128") ? String(localized: "Cancelled") : String(localized: "Not authorized")) }
            } else {
                let codes = Self.exitCodes(r.out)
                for t in admin { finish(t, ok: codes[t.id] == "0", error: String(localized: "Code \(codes[t.id] ?? "?")")) }
            }
        }
        running = false
    }

    /// One script for every administrator task (a single password prompt). Each task's output is
    /// discarded; only "<id>:<exit code>" lines come back.
    nonisolated static func adminScript(_ tasks: [MaintenanceTask]) -> String {
        tasks.map { "(\($0.command)) >/dev/null 2>&1; echo \"\($0.id):$?\"" }.joined(separator: "; ")
    }

    nonisolated static func exitCodes(_ out: String) -> [String: String] {
        var codes: [String: String] = [:]
        for line in out.split(separator: "\n") {
            let p = line.split(separator: ":")
            if p.count == 2 { codes[String(p[0])] = String(p[1]) }
        }
        return codes
    }

    private func finish(_ t: MaintenanceTask, ok: Bool, error: String) {
        if ok {
            states[t.id] = .done
            defaults.set(Date(), forKey: "maint.\(t.id)")
        } else {
            states[t.id] = .failed(error.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80).description)
        }
    }
}
