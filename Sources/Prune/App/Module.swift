import SwiftUI

enum ModuleSection: String, CaseIterable {
    case none = ""
    case cleanup, protection, system, applications, files

    var title: String {
        switch self {
        case .none: ""
        case .cleanup: String(localized: "Cleanup")
        case .protection: String(localized: "Protection")
        case .system: String(localized: "System")
        case .applications: String(localized: "Applications")
        case .files: String(localized: "Files")
        }
    }
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
        case .smartScan: String(localized: "Smart Scan")
        case .dashboard: String(localized: "Dashboard")
        case .systemJunk: String(localized: "System Junk")
        case .mailAttachments: String(localized: "Mail Attachments")
        case .trashBins: String(localized: "Trash Bins")
        case .privacy: String(localized: "Privacy")
        case .optimization: String(localized: "Optimization")
        case .maintenance: String(localized: "Maintenance")
        case .uninstaller: String(localized: "Uninstaller")
        case .updater: String(localized: "Updater")
        case .extensions: String(localized: "Extensions")
        case .spaceLens: String(localized: "Space Lens")
        case .largeFiles: String(localized: "Large & Old Files")
        case .duplicates: String(localized: "Duplicates")
        case .shredder: String(localized: "Shredder")
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
        case .optimization, .maintenance: .system
        case .uninstaller, .updater, .extensions: .applications
        case .spaceLens, .largeFiles, .duplicates, .shredder: .files
        }
    }
}
