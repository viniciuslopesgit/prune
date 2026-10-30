import Foundation
import Combine

@MainActor
final class DuplicatesModel: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case exact, similar
        var id: String { rawValue }
        var title: String { self == .exact ? String(localized: "Duplicates") : String(localized: "Similar photos") }
    }

    @Published var mode: Mode = .exact
    @Published var roots: [URL] = [URL.home("Downloads"), URL.home("Documents"), URL.home("Desktop"), URL.home("Pictures")].filter(\.exists)
    @Published var groups: [DupGroup] = []
    @Published var marked: Set<String> = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var progressText = ""
    @Published var minKB = 100
    @Published var similarity: Double = 0.45
    @Published var message: String?
    @Published var focusedGroup: UUID?

    var markedSize: Int64 {
        groups.flatMap(\.files).filter { marked.contains($0.id) }.reduce(0) { $0 + $1.size }
    }
    var wasted: Int64 { groups.reduce(0) { $0 + $1.wasted } }

    func scan() async {
        scanning = true
        marked = []
        let reporter = ProgressReporter { [weak self] in self?.progressText = $0 }
        let roots = self.roots, minSize = Int64(minKB) * 1024, mode = self.mode, threshold = Float(similarity)
        if mode == .exact {
            groups = await Task.detached(priority: .userInitiated) {
                DuplicateFinder.find(in: roots, minSize: minSize, progress: reporter)
            }.value
        } else {
            let r = await Task.detached(priority: .userInitiated) {
                DuplicateFinder.similarPhotos(in: roots, threshold: threshold, progress: reporter)
            }.value
            groups = r.groups
            message = Self.unreadableMessage(analysed: r.analysed, unreadable: r.unreadable, error: r.firstError)
        }
        if mode == .exact { autoSelect() }
        focusedGroup = groups.first?.id
        scanning = false
        scanned = true
    }

    /// Warning when Vision cannot analyze photos: without it, "nothing found" would be misleading.
    nonisolated static func unreadableMessage(analysed: Int, unreadable: Int, error: String?) -> String? {
        guard unreadable > 0 else { return nil }
        if analysed == 0 {
            return error.map { String(localized: "Could not analyze the photos on this Mac (\($0)).") }
                ?? String(localized: "Could not analyze the photos on this Mac.")
        }
        return Fmt.count(unreadable, String(localized: "photo could not be analyzed"), String(localized: "photos could not be analyzed")) + "."
    }

    func reset() {
        groups = []
        marked = []
        focusedGroup = nil
        scanned = false
    }

    /// Selects every copy except the oldest in each group.
    func autoSelect() {
        marked = Set(groups.filter { !$0.similar }.flatMap { $0.files.dropFirst().map(\.id) })
    }

    func toggle(_ f: DupFile) {
        if marked.contains(f.id) { marked.remove(f.id) } else { marked.insert(f.id) }
    }

    func removeMarked() async {
        // Never deletes every copy in a group: if they are all marked, the first one stays.
        let urls = groups.flatMap { group -> [URL] in
            let files = group.files.allSatisfy { marked.contains($0.id) } ? Array(group.files.dropFirst()) : group.files
            return files.filter { marked.contains($0.id) }.map(\.url)
        }
        let r = await Cleaner.remove(urls: urls, mode: AppSettings.shared.filesDeleteMode)
        let removed = Set(urls.map(\.path)).subtracting(r.failed.map(\.path))
        for i in groups.indices { groups[i].files.removeAll { removed.contains($0.id) } }
        groups.removeAll { $0.files.count < 2 }
        marked.subtract(removed)
        message = Fmt.freedMessage(r.freed, failed: r.failed.count)
    }
}
