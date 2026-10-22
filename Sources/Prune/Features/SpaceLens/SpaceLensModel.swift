import Foundation
import Observation

@MainActor
@Observable
final class SpaceLensModel {
    var root: DiskNode?
    var current: DiskNode?
    var scanning = false
    var progressText = ""
    var target: URL = home
    var marked: Set<DiskNode> = []
    var hovered: DiskNode?
    var message: String?
    private var scanner: SpaceScanner?

    var volumes: [URL] {
        let keys: [URLResourceKey] = [.volumeNameKey]
        return FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
    }

    func scan(_ url: URL) async {
        target = url
        scanning = true
        marked = []
        progressText = "A iniciar…"
        let reporter = ProgressReporter { [weak self] in self?.progressText = $0 }
        let scanner = SpaceScanner(progress: reporter)
        self.scanner = scanner
        let node = await Task.detached(priority: .userInitiated) { scanner.scan(url) }.value
        root = node
        current = node
        scanning = false
        self.scanner = nil
    }

    func cancel() {
        scanner?.cancelled = true
    }

    func reset() {
        root = nil
        current = nil
        hovered = nil
        marked = []
        scanner = nil
    }

    var markedSize: Int64 { marked.reduce(0) { $0 + $1.size } }

    func removeMarked() async {
        let nodes = Array(marked)
        let r = await Cleaner.remove(urls: nodes.map(\.url), mode: AppSettings.shared.filesDeleteMode)
        for n in nodes where !r.failed.contains(n.url) {
            guard let parent = n.parent else { continue }
            parent.children.removeAll { $0 == n }
            var p: DiskNode? = parent
            while let cur = p { cur.size -= n.size; p = cur.parent }
        }
        marked = []
        message = r.failed.isEmpty ? "Removido: \(Fmt.bytes(r.freed))." : "\(r.failed.count) item(ns) não puderam ser removidos."
        // Força atualização da vista.
        let c = current
        current = nil
        current = c
    }
}
