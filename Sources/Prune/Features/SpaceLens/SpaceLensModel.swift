import Foundation
import Combine

@MainActor
final class SpaceLensModel: ObservableObject {
    @Published var root: DiskNode?
    @Published var current: DiskNode?
    @Published var scanning = false
    @Published var progressText = ""
    @Published var target: URL = home
    @Published var marked: Set<DiskNode> = []
    @Published var hovered: DiskNode?
    @Published var message: String?
    private var scanner: SpaceScanner?

    var volumes: [URL] {
        let keys: [URLResourceKey] = [.volumeNameKey]
        return FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
    }

    func scan(_ url: URL) async {
        target = url
        scanning = true
        marked = []
        progressText = String(localized: "Starting…")
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
        // An item inside a folder that is also marked already goes with the folder.
        let nodes = marked.filter { node in
            var p = node.parent
            while let cur = p { if marked.contains(cur) { return false }; p = cur.parent }
            return true
        }
        let r = await Cleaner.remove(urls: nodes.map(\.url), mode: AppSettings.shared.filesDeleteMode)
        for n in nodes where !r.failed.contains(n.url) {
            guard let parent = n.parent else { continue }
            parent.children.removeAll { $0 == n }
            var p: DiskNode? = parent
            while let cur = p { cur.size -= n.size; p = cur.parent }
        }
        marked = []
        message = Fmt.freedMessage(r.freed, failed: r.failed.count)
        // Forces the view to refresh.
        let c = current
        current = nil
        current = c
    }
}
