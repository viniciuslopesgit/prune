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

    /// Aviso quando o Vision não consegue analisar fotografias: sem ele, "nada encontrado" seria enganador.
    nonisolated static func unreadableMessage(analysed: Int, unreadable: Int, error: String?) -> String? {
        guard unreadable > 0 else { return nil }
        if analysed == 0 {
            return "Não foi possível analisar as fotografias neste Mac" + (error.map { " (\($0))" } ?? "") + "."
        }
        return "\(Fmt.count(unreadable, "fotografia não pôde ser analisada", "fotografias não puderam ser analisadas"))."
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
        // Nunca apaga todas as cópias de um grupo: se estiverem todas marcadas, a primeira fica.
        let urls = groups.flatMap { group -> [URL] in
            let files = group.files.allSatisfy { marked.contains($0.id) } ? Array(group.files.dropFirst()) : group.files
            return files.filter { marked.contains($0.id) }.map(\.url)
        }
        let r = await Cleaner.remove(urls: urls, mode: AppSettings.shared.filesDeleteMode)
        let removed = Set(urls.map(\.path)).subtracting(r.failed.map(\.path))
        for i in groups.indices { groups[i].files.removeAll { removed.contains($0.id) } }
        groups.removeAll { $0.files.count < 2 }
        marked.subtract(removed)
        message = "\(Fmt.bytes(r.freed)) libertados." + (r.failed.isEmpty ? "" : " \(Fmt.count(r.failed.count, "ficheiro não foi removido", "ficheiros não foram removidos")).")
    }
}
