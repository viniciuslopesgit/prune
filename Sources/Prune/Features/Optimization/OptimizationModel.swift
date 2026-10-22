import Foundation
import Observation

@MainActor
@Observable
final class OptimizationModel {
    enum Tab: String, CaseIterable, Identifiable {
        case loginItems = "Itens de início de sessão"
        case agents = "Agentes de arranque"
        case heavy = "Grandes consumidores"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .loginItems: "person.badge.key"
            case .agents: "bolt.horizontal"
            case .heavy: "flame"
            }
        }
    }

    var tab: Tab = .loginItems
    var loginItems: [LoginItem] = []
    var launchItems: [LaunchItem] = []
    var processes: [ProcessInfoRow] = []
    var loading = false
    var loaded = false
    var loadingLoginItems = false
    var message: String?
    var sortByMemory = false

    func load() async {
        loading = true
        async let la = OptimizationService.launchItems()
        async let pr = OptimizationService.processes()
        launchItems = await la
        processes = await pr
        loading = false
        loaded = true
        // Pode esperar pela autorização de Automação (System Events), por isso vem por último.
        loadingLoginItems = true
        loginItems = await OptimizationService.loginItems()
        loadingLoginItems = false
    }

    func refreshProcesses() async {
        processes = await OptimizationService.processes()
    }

    var topProcesses: [ProcessInfoRow] {
        let sorted = sortByMemory ? processes.sorted { $0.memory > $1.memory } : processes.sorted { $0.cpu > $1.cpu }
        return Array(sorted.prefix(25))
    }

    func toggle(_ item: LaunchItem) async {
        let ok = await OptimizationService.setEnabled(item, enabled: item.disabled)
        if !ok { message = "Não foi possível alterar \(item.label)." }
        launchItems = await OptimizationService.launchItems()
    }

    func remove(_ item: LaunchItem) async {
        if !(await OptimizationService.remove(item)) { message = "Não foi possível remover \(item.label)." }
        launchItems = await OptimizationService.launchItems()
    }

    func remove(_ item: LoginItem) async {
        if !(await OptimizationService.removeLoginItem(item)) {
            message = "Não foi possível remover \(item.name). Autorize o Prune em Automação ▸ System Events."
        }
        loginItems = await OptimizationService.loginItems()
    }
}
