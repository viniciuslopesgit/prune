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

    /// Liberta os resultados que ocupam mais memória (árvore da Lente de Espaço, duplicados,
    /// ficheiros grandes, caches de imagens). Chamado quando a janela fecha — a app continua
    /// na barra de menus — ou quando o macOS avisa que a memória está a acabar.
    func releaseHeavyResults() {
        if !spaceLens.scanning { spaceLens.reset() }
        if !duplicates.scanning { duplicates.reset() }
        if !largeFiles.scanning && !largeFiles.working { largeFiles.reset() }
        if !uninstaller.working { uninstaller.releaseDetails() }
        FS.clearCaches()
        Thumbnails.clear()
    }
}
