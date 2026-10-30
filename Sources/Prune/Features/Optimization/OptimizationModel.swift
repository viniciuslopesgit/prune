import Foundation
import Combine

@MainActor
final class OptimizationModel: ObservableObject {
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

    @Published var tab: Tab = .loginItems
    @Published var loginItems: [LoginItem] = []
    @Published var launchItems: [LaunchItem] = []
    @Published var processes: [ProcessInfoRow] = []
    @Published var loading = false
    @Published var loaded = false
    @Published var loadingLoginItems = false
    @Published var message: String?
    @Published var sortByMemory = false

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
