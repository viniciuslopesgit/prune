import Foundation
import Observation

@MainActor
@Observable
final class OptimizationModel {
    enum Tab: String, CaseIterable, Identifiable {
        case loginItems, agents, heavy
        var id: String { rawValue }
        var title: String {
            switch self {
            case .loginItems: String(localized: "Login items")
            case .agents: String(localized: "Launch agents")
            case .heavy: String(localized: "Heavy consumers")
            }
        }
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
        // May wait for the Automation authorization (System Events), so it comes last.
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
        if !ok { message = String(localized: "Could not change \(item.label).") }
        launchItems = await OptimizationService.launchItems()
    }

    func remove(_ item: LaunchItem) async {
        if !(await OptimizationService.remove(item)) { message = String(localized: "Could not remove \(item.label).") }
        launchItems = await OptimizationService.launchItems()
    }

    func remove(_ item: LoginItem) async {
        if !(await OptimizationService.removeLoginItem(item)) {
            message = String(localized: "Could not remove \(item.name). Allow Prune in Automation ▸ System Events.")
        }
        loginItems = await OptimizationService.loginItems()
    }
}
