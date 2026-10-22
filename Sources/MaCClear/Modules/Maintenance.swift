import AppKit
import Foundation
import Observation

struct MaintenanceTask: Identifiable {
    let id: String
    let title: String
    let icon: String
    let description: String
    let requiresAdmin: Bool
    let command: String
    /// De quantos em quantos dias é recomendado executar.
    let recommendedDays: Int
    /// App que tem de estar fechada (bundle ID).
    var requiresClosed: String?
}

enum MaintenanceCatalog {
    static let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    static let tasks: [MaintenanceTask] = [
        .init(id: "purgeable", title: "Libertar espaço purgável", icon: "externaldrive.badge.minus",
              description: "Remove instantâneos locais do Time Machine e outros dados purgáveis, devolvendo espaço livre ao disco.",
              requiresAdmin: true, command: "/usr/bin/tmutil thinlocalsnapshots / 999999999999 4", recommendedDays: 14),
        .init(id: "dns", title: "Limpar a cache de DNS", icon: "network",
              description: "Resolve problemas de sites que não abrem ou que abrem a versão errada, limpando a cache de nomes de domínio.",
              requiresAdmin: true, command: "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder", recommendedDays: 30),
        .init(id: "spotlight", title: "Reindexar o Spotlight", icon: "magnifyingglass",
              description: "Reconstrói o índice do Spotlight. Útil quando as pesquisas são lentas ou não encontram ficheiros. Pode demorar algumas horas em segundo plano.",
              requiresAdmin: true, command: "/usr/bin/mdutil -E /", recommendedDays: 90),
        .init(id: "launchservices", title: "Reconstruir Launch Services", icon: "square.stack.3d.up",
              description: "Corrige entradas duplicadas no menu \"Abrir com\" e associações de ficheiros erradas.",
              requiresAdmin: false, command: "\(lsregister) -r -domain local -domain system -domain user", recommendedDays: 60),
        .init(id: "quicklook", title: "Limpar a cache do Quick Look", icon: "eye",
              description: "Repõe as pré-visualizações e miniaturas de ficheiros quando aparecem erradas ou em branco.",
              requiresAdmin: false, command: "/usr/bin/qlmanage -r cache; /usr/bin/qlmanage -r", recommendedDays: 30),
        .init(id: "fonts", title: "Limpar a cache de tipos de letra", icon: "textformat",
              description: "Resolve texto com tipos de letra corrompidos ou trocados. Recomenda-se reiniciar a seguir.",
              requiresAdmin: false, command: "/usr/bin/atsutil databases -removeUser", recommendedDays: 90),
        .init(id: "mail", title: "Acelerar o Mail", icon: "envelope.open",
              description: "Compacta a base de dados de mensagens do Mail, tornando as pesquisas e a navegação mais rápidas. O Mail tem de estar fechado.",
              requiresAdmin: false,
              command: "for f in ~/Library/Mail/V*/MailData/Envelope\\ Index; do [ -f \"$f\" ] && /usr/bin/sqlite3 \"$f\" 'VACUUM;'; done; true",
              recommendedDays: 30, requiresClosed: "com.apple.mail"),
        .init(id: "verify", title: "Verificar o disco de arranque", icon: "internaldrive",
              description: "Verifica a estrutura do sistema de ficheiros do disco de arranque e reporta erros.",
              requiresAdmin: true, command: "/usr/sbin/diskutil verifyVolume /", recommendedDays: 60),
        .init(id: "permissions", title: "Reparar permissões da pasta pessoal", icon: "lock.shield",
              description: "Repõe as permissões corretas dos ficheiros da sua pasta pessoal. Resolve erros de acesso em apps.",
              requiresAdmin: false, command: "/usr/sbin/diskutil resetUserPermissions / $(id -u)", recommendedDays: 180),
        .init(id: "dock", title: "Reiniciar Dock e Finder", icon: "dock.rectangle",
              description: "Reinicia o Dock, o Finder e a barra de menus quando ficam lentos ou com falhas visuais.",
              requiresAdmin: false, command: "/usr/bin/killall Dock; /usr/bin/killall Finder; /usr/bin/killall SystemUIServer; true", recommendedDays: 0),
    ]
}

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

    /// Tarefas recomendadas que a Análise Inteligente pode executar sem perguntar nada,
    /// a não ser que o utilizador autorize tarefas de administrador nas Definições.
    var recommendedForSmartScan: [MaintenanceTask] {
        recommended.filter { !$0.requiresAdmin || AppSettings.shared.smartScanAdminTasks }
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
