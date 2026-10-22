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
            if SafetyGuard.canDelete(u) { items.append(u) } else { message = "\(u.lastPathComponent) está protegido e não pode ser destruído." }
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
        message = failed.isEmpty ? "\(done) item(ns) destruídos de forma segura." : "\(done) destruídos · \(failed.count) não puderam ser destruídos."
        working = false
    }
}
