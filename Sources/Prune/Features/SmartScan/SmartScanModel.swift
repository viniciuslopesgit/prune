import Foundation
import Combine

/// Smart Scan: cleanup + protection status in a single click.
@MainActor
final class SmartScanModel: ObservableObject {
    enum Phase { case idle, scanning, results, running, done }

    @Published var phase: Phase = .idle
    @Published var step = ""
    @Published var progressText = ""
    @Published var junk: [CleanCategory] = []
    @Published var security = SecurityStatus()
    @Published var cleanReport = CleanReport()
    @Published var runCleanup = true

    var junkSize: Int64 { junk.reduce(0) { $0 + $1.selectedSize } }

    func scan() async {
        phase = .scanning
        let reporter = ProgressReporter { [weak self] in self?.progressText = $0 }

        step = String(localized: "Cleanup")
        let junk = await Task.detached {
            await SystemJunkScanner.scan(reporter) + TrashScanner.scan(reporter)
        }.value
        self.junk = junk.filter { $0.selectedSize > 0 }

        step = String(localized: "Protection")
        progressText = String(localized: "Checking macOS protections…")
        security = await SystemProtection.status()

        runCleanup = !self.junk.isEmpty
        phase = .results
        Analytics.track("scan_complete", ["module": "smartScan", "found_mb": Analytics.mb(junkSize),
                                          "protections_off": security.disabledCount])
    }

    func run() async {
        phase = .running
        cleanReport = CleanReport()
        if runCleanup {
            step = String(localized: "Cleaning…")
            for cat in junk {
                let items = cat.items.filter(\.selected)
                progressText = cat.name
                let mode = cat.id.hasPrefix("userTrash") || cat.id.hasPrefix("trash-") ? DeleteMode.permanent : AppSettings.shared.junkDeleteMode
                let r = await Task.detached { await Cleaner.remove(items, mode: mode) }.value
                cleanReport.merge(r)
            }
        }
        phase = .done
        Analytics.track("clean_complete", ["module": "smartScan", "freed_mb": Analytics.mb(cleanReport.freed),
                                           "items_removed": cleanReport.removed])
    }
}
