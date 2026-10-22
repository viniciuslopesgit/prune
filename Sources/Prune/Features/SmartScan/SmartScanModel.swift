import Foundation
import Observation

/// Análise Inteligente: limpeza + estado das proteções num só clique.
@MainActor
@Observable
final class SmartScanModel {
    enum Phase { case idle, scanning, results, running, done }

    var phase: Phase = .idle
    var step = ""
    var progressText = ""
    var junk: [CleanCategory] = []
    var security = SecurityStatus()
    var cleanReport = CleanReport()
    var runCleanup = true

    var junkSize: Int64 { junk.reduce(0) { $0 + $1.selectedSize } }

    func scan() async {
        phase = .scanning
        let reporter = ProgressReporter { [weak self] in self?.progressText = $0 }

        step = "Limpeza"
        let junk = await Task.detached {
            await SystemJunkScanner.scan(reporter) + TrashScanner.scan(reporter)
        }.value
        self.junk = junk.filter { $0.selectedSize > 0 }

        step = "Proteção"
        progressText = "A verificar as proteções do macOS…"
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
            step = "A limpar…"
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
