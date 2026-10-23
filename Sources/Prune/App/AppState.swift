import Foundation

@MainActor
@Observable
final class AppState {
    static let shared = AppState()
    var selection: Module = .smartScan

    let smartScan = SmartScanModel()
    let systemJunk = CleanupModel(mode: { AppSettings.shared.junkDeleteMode }, scanner: { await SystemJunkScanner.scan($0) })
    let mail = CleanupModel(mode: { AppSettings.shared.junkDeleteMode }, scanner: { await MailAttachmentsScanner.scan($0) })
    let trash = CleanupModel(mode: { .permanent }, scanner: { await TrashScanner.scan($0) })
    let privacy: CleanupModel = {
        let m = CleanupModel(mode: { .permanent }, scanner: { await PrivacyScanner.scan($0) })
        m.appsToClose = PrivacyScanner.browserBundleIDs
        return m
    }()
    let optimization = OptimizationModel()
    let maintenance = MaintenanceModel()
    let uninstaller = UninstallerModel()
    let updater = UpdaterModel()
    let extensions = ExtensionsModel()
    let spaceLens = SpaceLensModel()
    let largeFiles = LargeFilesModel()
    let duplicates = DuplicatesModel()
    let shredder = ShredderModel()

    init() {
        systemJunk.analyticsName = Module.systemJunk.rawValue
        mail.analyticsName = Module.mailAttachments.rawValue
        trash.analyticsName = Module.trashBins.rawValue
        privacy.analyticsName = Module.privacy.rawValue
    }

    /// Frees the results that take up the most memory (Space Lens tree, duplicates,
    /// large files, image caches). Called when the window closes — the app stays
    /// in the menu bar — or when macOS warns that memory is running low.
    func releaseHeavyResults() {
        if !spaceLens.scanning { spaceLens.reset() }
        if !duplicates.scanning { duplicates.reset() }
        if !largeFiles.scanning && !largeFiles.working { largeFiles.reset() }
        if !uninstaller.working { uninstaller.releaseDetails() }
        FS.clearCaches()
        Thumbnails.clear()
    }
}
