import AppKit
import Observation

/// Generic model used by the category-based cleanup modules
/// (System Junk, Mail Attachments, Trash Bins, Privacy).
@MainActor
@Observable
final class CleanupModel {
    enum Phase { case idle, scanning, results, cleaning, done }

    var phase: Phase = .idle
    var categories: [CleanCategory] = []
    var selectedCategoryID: String?
    var progressText = ""
    var report = CleanReport()
    var lastScan: Date?
    /// Apps that must be closed before cleaning (bundle IDs → name).
    var appsToClose: [String: String] = [:]
    /// Module name in the statistics (e.g. "systemJunk").
    var analyticsName = ""

    private let scanner: @Sendable (ProgressReporter) async -> [CleanCategory]
    private let modeProvider: () -> DeleteMode

    init(mode: @escaping () -> DeleteMode, scanner: @escaping @Sendable (ProgressReporter) async -> [CleanCategory]) {
        self.scanner = scanner
        self.modeProvider = mode
    }

    var totalSize: Int64 { categories.reduce(0) { $0 + $1.totalSize } }
    var selectedSize: Int64 { categories.reduce(0) { $0 + $1.selectedSize } }
    var selectedCount: Int { categories.reduce(0) { $0 + $1.selectedCount } }

    var selectedCategory: CleanCategory? {
        categories.first { $0.id == selectedCategoryID }
    }

    func scan() async {
        phase = .scanning
        progressText = String(localized: "Preparing…")
        let reporter = ProgressReporter { [weak self] t in self?.progressText = t }
        let scanner = self.scanner
        let result = await Task.detached(priority: .userInitiated) { await scanner(reporter) }.value
        categories = result.filter { !$0.items.isEmpty }
        selectedCategoryID = categories.first?.id
        lastScan = Date()
        phase = .results
        Analytics.track("scan_complete", ["module": analyticsName, "found_mb": Analytics.mb(totalSize),
                                          "categories": categories.count])
    }

    func clean() async {
        phase = .cleaning
        let mode = modeProvider()
        var total = CleanReport()
        for cat in categories {
            let items = cat.items.filter(\.selected)
            guard !items.isEmpty else { continue }
            progressText = String(localized: "Cleaning \(cat.name)…")
            let r = await Task.detached { await Cleaner.remove(items, mode: mode) }.value
            total.merge(r)
        }
        report = total
        Analytics.track("clean_complete", ["module": analyticsName, "freed_mb": Analytics.mb(total.freed),
                                           "items_removed": total.removed, "failed": total.failed.count])
        let removed = Set(categories.flatMap { $0.items.filter(\.selected).map(\.url) }).subtracting(total.failed)
        dropItems(removed)
        phase = .done
    }

    private func dropItems(_ urls: Set<URL>) {
        for i in categories.indices { categories[i].items.removeAll { urls.contains($0.url) } }
        categories.removeAll { $0.items.isEmpty }
        if selectedCategory == nil { selectedCategoryID = categories.first?.id }
    }

    func retryFailedAsAdmin() async {
        let failed = report.failed.filter { $0.isFileURL && $0.path != "/" }
        guard !failed.isEmpty else { return }
        let r = await Cleaner.retryAsAdmin(failed, mode: modeProvider())
        report.freed += r.freed
        report.removed += r.removed
        report.failed = r.failed
        dropItems(Set(failed).subtracting(r.failed))
    }

    func reset() {
        phase = .idle
        categories = []
        report = CleanReport()
    }

    // MARK: Selection

    func toggleCategory(_ id: String) {
        guard let i = categories.firstIndex(where: { $0.id == id }) else { return }
        let newValue = !categories[i].allSelected
        for j in categories[i].items.indices { categories[i].items[j].selected = newValue }
    }

    func toggleItem(category: String, item: UUID) {
        guard let i = categories.firstIndex(where: { $0.id == category }),
              let j = categories[i].items.firstIndex(where: { $0.id == item }) else { return }
        categories[i].items[j].selected.toggle()
    }

    func setAll(_ value: Bool) {
        for i in categories.indices {
            for j in categories[i].items.indices { categories[i].items[j].selected = value }
        }
    }

    /// Open apps that block the cleanup.
    var runningBlockers: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            guard let id = $0.bundleIdentifier else { return false }
            return appsToClose.keys.contains(id)
        }
    }
}
