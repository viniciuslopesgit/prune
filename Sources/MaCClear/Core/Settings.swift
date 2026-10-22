import Foundation
import Observation
import ServiceManagement

enum DeleteMode: String, CaseIterable, Identifiable {
    case trash, permanent
    var id: String { rawValue }
    var title: String { self == .trash ? "Mover para o Lixo" : "Apagar definitivamente" }
}

@Observable
final class AppSettings {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    /// Caches, logs e lixo regenerável.
    var junkDeleteMode: DeleteMode {
        didSet { d.set(junkDeleteMode.rawValue, forKey: "junkDeleteMode") }
    }
    /// Ficheiros do utilizador (grandes, duplicados, apps).
    var filesDeleteMode: DeleteMode {
        didSet { d.set(filesDeleteMode.rawValue, forKey: "filesDeleteMode") }
    }
    var ignoredPaths: [String] {
        didSet { d.set(ignoredPaths, forKey: "ignoredPaths") }
    }
    var largeFileMinMB: Int {
        didSet { d.set(largeFileMinMB, forKey: "largeFileMinMB") }
    }
    var shredPasses: Int {
        didSet { d.set(shredPasses, forKey: "shredPasses") }
    }
    var smartScanRunsMaintenance: Bool {
        didSet { d.set(smartScanRunsMaintenance, forKey: "smartScanRunsMaintenance") }
    }
    /// Incluir na Análise Inteligente tarefas que pedem a palavra-passe de administrador.
    var smartScanAdminTasks: Bool {
        didSet { d.set(smartScanAdminTasks, forKey: "smartScanAdminTasks") }
    }
    /// O utilizador escolheu não ver o assistente de Acesso Total ao Disco.
    var fdaOnboardingDismissed: Bool {
        didSet { d.set(fdaOnboardingDismissed, forKey: "fdaOnboardingDismissed") }
    }

    /// Estatísticas de utilização anónimas (Google Analytics). Desligado até o utilizador aceitar.
    var analyticsEnabled: Bool {
        didSet {
            d.set(analyticsEnabled, forKey: "analyticsEnabled")
            // Ao recusar, esquece o identificador aleatório desta instalação.
            if !analyticsEnabled { d.removeObject(forKey: Analytics.clientIDKey) }
        }
    }
    /// O utilizador já respondeu ao pedido de estatísticas (sim ou não).
    var analyticsAsked: Bool {
        didSet { d.set(analyticsAsked, forKey: "analyticsAsked") }
    }

    private init() {
        junkDeleteMode = DeleteMode(rawValue: d.string(forKey: "junkDeleteMode") ?? "") ?? .permanent
        filesDeleteMode = DeleteMode(rawValue: d.string(forKey: "filesDeleteMode") ?? "") ?? .trash
        ignoredPaths = d.stringArray(forKey: "ignoredPaths") ?? []
        largeFileMinMB = d.object(forKey: "largeFileMinMB") as? Int ?? 50
        shredPasses = d.object(forKey: "shredPasses") as? Int ?? 1
        smartScanRunsMaintenance = d.object(forKey: "smartScanRunsMaintenance") as? Bool ?? true
        smartScanAdminTasks = d.object(forKey: "smartScanAdminTasks") as? Bool ?? false
        fdaOnboardingDismissed = d.bool(forKey: "fdaOnboardingDismissed")
        analyticsEnabled = d.bool(forKey: "analyticsEnabled")
        analyticsAsked = d.bool(forKey: "analyticsAsked")
    }

    func isIgnored(_ path: String) -> Bool {
        ignoredPaths.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Launch at login: \(error)")
            }
        }
    }
}
