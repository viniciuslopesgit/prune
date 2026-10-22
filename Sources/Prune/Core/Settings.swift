import Foundation
import Observation
import ServiceManagement

enum DeleteMode: String, CaseIterable, Identifiable {
    case trash, permanent
    var id: String { rawValue }
    var title: String { self == .trash ? String(localized: "Move to Trash") : String(localized: "Delete permanently") }
}

@Observable
final class AppSettings {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    /// Caches, logs and regenerable junk.
    var junkDeleteMode: DeleteMode {
        didSet { d.set(junkDeleteMode.rawValue, forKey: "junkDeleteMode") }
    }
    /// User files (large files, duplicates, apps).
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
    /// The user chose not to see the Full Disk Access assistant.
    var fdaOnboardingDismissed: Bool {
        didSet { d.set(fdaOnboardingDismissed, forKey: "fdaOnboardingDismissed") }
    }

    /// Anonymous usage statistics (Google Analytics). Off until the user accepts.
    var analyticsEnabled: Bool {
        didSet {
            d.set(analyticsEnabled, forKey: "analyticsEnabled")
            // When declining, forgets this installation's random identifier.
            if !analyticsEnabled { d.removeObject(forKey: Analytics.clientIDKey) }
        }
    }
    /// The user has already answered the statistics prompt (yes or no).
    var analyticsAsked: Bool {
        didSet { d.set(analyticsAsked, forKey: "analyticsAsked") }
    }

    private init() {
        junkDeleteMode = DeleteMode(rawValue: d.string(forKey: "junkDeleteMode") ?? "") ?? .permanent
        filesDeleteMode = DeleteMode(rawValue: d.string(forKey: "filesDeleteMode") ?? "") ?? .trash
        ignoredPaths = d.stringArray(forKey: "ignoredPaths") ?? []
        largeFileMinMB = d.object(forKey: "largeFileMinMB") as? Int ?? 50
        shredPasses = d.object(forKey: "shredPasses") as? Int ?? 1
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
