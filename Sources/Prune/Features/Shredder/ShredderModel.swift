import Foundation
import Observation

@MainActor
@Observable
final class ShredderModel {
    var items: [URL] = []
    var working = false
    var message: String?

    var totalSize: Int64 { items.reduce(0) { $0 + FS.size(of: $1) } }

    func add(_ urls: [URL]) {
        for u in urls where !items.contains(u) {
            if SafetyGuard.canDelete(u) { items.append(u) } else { message = "\(u.lastPathComponent) está protegido." }
        }
    }

    func shredAll() async {
        working = true
        var failed: [URL] = []
        let passes = AppSettings.shared.shredPasses
        for url in items {
            if !(await Shredder.shred(url, passes: passes)) { failed.append(url) }
        }
        let done = items.count - failed.count
        items = failed
        message = failed.isEmpty ? "\(Fmt.count(done, "item destruído", "itens destruídos"))." : "\(Fmt.count(done, "item destruído", "itens destruídos")). \(Fmt.count(failed.count, "não foi destruído", "não foram destruídos"))."
        working = false
    }
}
