import AppKit
import Observation

@MainActor
@Observable
final class MaintenanceModel {
    enum TaskState: Equatable { case idle, running, done, failed(String) }

    var selected: Set<String> = []
    var states: [String: TaskState] = [:]
    var running = false
    var focused: String? = MaintenanceCatalog.tasks.first?.id

    private let defaults = UserDefaults.standard

    init() {
        // Por defeito só tarefas que não pedem palavra-passe.
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
                states[t.id] = .failed("Feche a app primeiro")
                continue
            }
            let r = await Shell.zsh(t.command)
            finish(t, ok: r.ok || t.id == "dock", error: r.err)
        }

        let admin = tasks.filter(\.requiresAdmin)
        if !admin.isEmpty {
            // Um único pedido de palavra-passe para todas as tarefas de administrador.
            let script = admin.map { "(\($0.command)) >/dev/null 2>&1; echo \"\($0.id):$?\"" }.joined(separator: "; ")
            let r = await Shell.admin(script)
            if !r.ok && r.out.isEmpty {
                for t in admin { states[t.id] = .failed(r.err.contains("-128") ? "Cancelado" : "Sem autorização") }
            } else {
                var codes: [String: String] = [:]
                for line in r.out.split(separator: "\n") {
                    let p = line.split(separator: ":")
                    if p.count == 2 { codes[String(p[0])] = String(p[1]) }
                }
                for t in admin { finish(t, ok: codes[t.id] == "0", error: "Código \(codes[t.id] ?? "?")") }
            }
        }
        running = false
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
