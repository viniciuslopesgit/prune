import Foundation
import Combine

@MainActor
final class ShredderModel: ObservableObject {
    @Published var items: [URL] = []
    @Published var working = false
    @Published var message: String?

    var totalSize: Int64 { items.reduce(0) { $0 + FS.size(of: $1) } }

    func add(_ urls: [URL]) {
        for u in urls where !items.contains(u) {
            if SafetyGuard.canDelete(u) { items.append(u) } else { message = String(localized: "\(u.lastPathComponent) is protected.") }
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
        let shredded = Fmt.count(done, String(localized: "item shredded"), String(localized: "items shredded")) + "."
        message = failed.isEmpty ? shredded : shredded + " " + Fmt.count(failed.count, String(localized: "was not shredded"), String(localized: "were not shredded")) + "."
        working = false
    }
}
