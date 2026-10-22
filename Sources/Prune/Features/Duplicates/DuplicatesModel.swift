import Foundation
import Observation

@MainActor
@Observable
final class DuplicatesModel {
    enum Mode: String, CaseIterable, Identifiable { case exact = "Duplicados", similar = "Fotografias semelhantes"; var id: String { rawValue } }

    var mode: Mode = .exact
    var roots: [URL] = [URL.home("Downloads"), URL.home("Documents"), URL.home("Desktop"), URL.home("Pictures")].filter(\.exists)
    var groups: [DupGroup] = []
    var marked: Set<String> = []
    var scanning = false
    var scanned = false
    var progressText = ""
    var minKB = 100
    var similarity: Double = 0.45
    var message: String?
    var focusedGroup: UUID?

    var markedSize: Int64 {
        groups.flatMap(\.files).filter { marked.contains($0.id) }.reduce(0) { $0 + $1.size }
    }
    var wasted: Int64 { groups.reduce(0) { $0 + $1.wasted } }

    func scan() async {
        scanning = true
        marked = []
        let reporter = ProgressReporter { [weak self] in self?.progressText = $0 }
        let roots = self.roots, minSize = Int64(minKB) * 1024, mode = self.mode, threshold = Float(similarity)
        groups = await Task.detached(priority: .userInitiated) {
            mode == .exact
                ? DuplicateFinder.find(in: roots, minSize: minSize, progress: reporter)
                : DuplicateFinder.similarPhotos(in: roots, threshold: threshold, progress: reporter)
        }.value
        if mode == .exact { autoSelect() }
        focusedGroup = groups.first?.id
        scanning = false
        scanned = true
    }

    func reset() {
        groups = []
        marked = []
        focusedGroup = nil
        scanned = false
    }

    /// Seleciona todas as cópias exceto a mais antiga de cada grupo.
    func autoSelect() {
        marked = Set(groups.filter { !$0.similar }.flatMap { $0.files.dropFirst().map(\.id) })
    }

    func toggle(_ f: DupFile) {
        if marked.contains(f.id) { marked.remove(f.id) } else { marked.insert(f.id) }
    }

    func removeMarked() async {
        let urls = groups.flatMap(\.files).filter { marked.contains($0.id) }.map(\.url)
        let r = await Cleaner.remove(urls: urls, mode: AppSettings.shared.filesDeleteMode)
        let removed = Set(urls.map(\.path)).subtracting(r.failed.map(\.path))
        for i in groups.indices { groups[i].files.removeAll { removed.contains($0.id) } }
        groups.removeAll { $0.files.count < 2 }
        marked.subtract(removed)
        message = "Libertados \(Fmt.bytes(r.freed))" + (r.failed.isEmpty ? "." : " · \(r.failed.count) falharam.")
    }
}
