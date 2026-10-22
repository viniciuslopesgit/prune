import SwiftUI

enum ModuleSection: String, CaseIterable {
    case none = ""
    case cleanup = "Limpeza"
    case protection = "Proteção"
    case speed = "Velocidade"
    case applications = "Aplicações"
    case files = "Ficheiros"
}

enum Module: String, CaseIterable, Identifiable, Hashable {
    case smartScan, dashboard
    case systemJunk, mailAttachments, trashBins
    case privacy
    case optimization, maintenance
    case uninstaller, updater, extensions
    case spaceLens, largeFiles, duplicates, shredder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartScan: "Análise Inteligente"
        case .dashboard: "Painel"
        case .systemJunk: "Lixo do Sistema"
        case .mailAttachments: "Anexos do Mail"
        case .trashBins: "Lixo"
        case .privacy: "Privacidade"
        case .optimization: "Otimização"
        case .maintenance: "Manutenção"
        case .uninstaller: "Desinstalador"
        case .updater: "Atualizador"
        case .extensions: "Extensões"
        case .spaceLens: "Lente de Espaço"
        case .largeFiles: "Grandes e Antigos"
        case .duplicates: "Duplicados"
        case .shredder: "Destruidor"
        }
    }

    var icon: String {
        switch self {
        case .smartScan: "sparkles"
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .systemJunk: "externaldrive.badge.xmark"
        case .mailAttachments: "paperclip"
        case .trashBins: "trash"
        case .privacy: "hand.raised"
        case .optimization: "slider.horizontal.3"
        case .maintenance: "wrench.and.screwdriver"
        case .uninstaller: "xmark.app"
        case .updater: "arrow.triangle.2.circlepath"
        case .extensions: "puzzlepiece.extension"
        case .spaceLens: "circle.hexagongrid"
        case .largeFiles: "doc.badge.clock"
        case .duplicates: "square.on.square"
        case .shredder: "scissors"
        }
    }

    var section: ModuleSection {
        switch self {
        case .smartScan, .dashboard: .none
        case .systemJunk, .mailAttachments, .trashBins: .cleanup
        case .privacy: .protection
        case .optimization, .maintenance: .speed
        case .uninstaller, .updater, .extensions: .applications
        case .spaceLens, .largeFiles, .duplicates, .shredder: .files
        }
    }

    var colors: [Color] {
        switch section {
        case .none: [Color(hex: 0x5B2A86), Color(hex: 0x2B1055)]
        case .cleanup: [Color(hex: 0x1E8C7E), Color(hex: 0x0B3D4F)]
        case .protection: [Color(hex: 0xB2365B), Color(hex: 0x4A1236)]
        case .speed: [Color(hex: 0xD9822B), Color(hex: 0x6B2A12)]
        case .applications: [Color(hex: 0x2F6FDB), Color(hex: 0x162E6E)]
        case .files: [Color(hex: 0x3AA0C8), Color(hex: 0x173C63)]
        }
    }

    var accent: Color { colors[0] }
}
