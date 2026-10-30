import Foundation
import Combine
import UniformTypeIdentifiers

enum FileKind: String, CaseIterable, Identifiable {
    case all, documents, videos, audio, images, archives, diskImages, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .documents: String(localized: "Documents")
        case .videos: String(localized: "Videos")
        case .audio: String(localized: "Audio")
        case .images: String(localized: "Images")
        case .archives: String(localized: "Archives")
        case .diskImages: String(localized: "Disk images")
        case .other: String(localized: "Other")
        }
    }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .documents: "doc.richtext"
        case .videos: "film"
        case .audio: "waveform"
        case .images: "photo"
        case .archives: "archivebox"
        case .diskImages: "opticaldiscdrive"
        case .other: "doc"
        }
    }

    static func of(_ type: UTType?) -> FileKind {
        guard let t = type else { return .other }
        if t.conforms(to: .movie) || t.conforms(to: .video) { return .videos }
        if t.conforms(to: .audio) { return .audio }
        if t.conforms(to: .image) { return .images }
        if t.conforms(to: .diskImage) || t.identifier == "com.apple.disk-image-udif" { return .diskImages }
        if t.conforms(to: .archive) { return .archives }
        if t.conforms(to: .pdf) || t.conforms(to: .presentation) || t.conforms(to: .spreadsheet) || t.conforms(to: .text) || t.conforms(to: .compositeContent) { return .documents }
        return .other
    }
}

enum FileAge: String, CaseIterable, Identifiable {
    case any, month, halfYear, year
    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: String(localized: "Any date")
        case .month: String(localized: "1+ month")
        case .halfYear: String(localized: "6+ months")
        case .year: String(localized: "1+ year")
        }
    }
    var cutoff: Date? {
        switch self {
        case .any: nil
        case .month: Date().addingTimeInterval(-30 * 86400)
        case .halfYear: Date().addingTimeInterval(-182 * 86400)
        case .year: Date().addingTimeInterval(-365 * 86400)
        }
    }
}

struct LargeFile: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let accessed: Date?
    let modified: Date?
    let kind: FileKind
}

@MainActor
final class LargeFilesModel: ObservableObject {
    @Published var files: [LargeFile] = []
    @Published var scanning = false
    @Published var scanned = false
    @Published var progressText = ""
    @Published var kind: FileKind = .all
    @Published var age: FileAge = .any
    @Published var minMB: Int = AppSettings.shared.largeFileMinMB
    @Published var includeLibrary = false
    @Published var roots: [URL] = [home]
    @Published var selected: Set<String> = []
    @Published var message: String?
    @Published var working = false

    var filtered: [LargeFile] {
        files.filter { f in
            (kind == .all || f.kind == kind)
                && f.size >= Int64(minMB) * 1_000_000
                && (age.cutoff.map { (f.accessed ?? f.modified ?? .distantPast) < $0 } ?? true)
        }
    }

    var selectedFiles: [LargeFile] { files.filter { selected.contains($0.id) } }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }

    func reset() {
        files = []
        selected = []
        scanned = false
    }

    func count(_ k: FileKind) -> Int {
        files.filter { (k == .all || $0.kind == k) && $0.size >= Int64(minMB) * 1_000_000 }.count
    }

    func scan() async {
        scanning = true
        selected = []
        let reporter = ProgressReporter { [weak self] in self?.progressText = $0 }
        let roots = self.roots, includeLibrary = self.includeLibrary
        // Scans from 10 MB up so the filter can change without a new scan.
        files = await Task.detached(priority: .userInitiated) {
            Self.find(in: roots, minSize: 10_000_000, includeLibrary: includeLibrary, progress: reporter)
        }.value
        scanning = false
        scanned = true
    }

    nonisolated static func find(in roots: [URL], minSize: Int64, includeLibrary: Bool, progress: ProgressReporter) -> [LargeFile] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey,
                                      .contentAccessDateKey, .contentModificationDateKey, .contentTypeKey, .isPackageKey]
        var result: [LargeFile] = []
        var n = 0
        for root in roots {
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                         errorHandler: { _, _ in true }) else { continue }
            let keySet = Set(keys)
            FS.forEach(e) { url in
                n += 1
                if n % 1000 == 0 { progress.report("\(Fmt.files(n)) · \(url.deletingLastPathComponent().displayPath)") }
                if !includeLibrary, url.path == home.path + "/Library" { e.skipDescendants(); return true }
                if url.path.hasPrefix(home.path + "/Library/Mobile Documents") || url.path.hasPrefix(home.path + "/.Trash") { e.skipDescendants(); return true }
                guard let rv = try? url.resourceValues(forKeys: keySet) else { return true }
                if rv.isDirectory == true && rv.isPackage != true { return true }
                let size: Int64
                if rv.isPackage == true {
                    // Packages (apps, photo libraries…) are only considered if they are project bundles, not apps.
                    if url.pathExtension == "app" || url.pathExtension == "photoslibrary" { return true }
                    size = FS.size(of: url)
                } else {
                    size = Int64(rv.totalFileAllocatedSize ?? rv.fileSize ?? 0)
                }
                guard size >= minSize, SafetyGuard.canDelete(url) else { return true }
                result.append(LargeFile(url: url, size: size, accessed: rv.contentAccessDate, modified: rv.contentModificationDate, kind: .of(rv.contentType)))
                return true
            }
        }
        return result.sorted { $0.size > $1.size }
    }

    func removeSelected(shred: Bool) async {
        working = true
        let targets = selectedFiles
        var failed: [URL] = []
        var freed: Int64 = 0
        if shred {
            for f in targets {
                if await Shredder.shred(f.url, passes: AppSettings.shared.shredPasses) { freed += f.size } else { failed.append(f.url) }
            }
        } else {
            let r = await Cleaner.remove(urls: targets.map(\.url), mode: AppSettings.shared.filesDeleteMode)
            freed = r.freed
            failed = r.failed
        }
        let removed = Set(targets.map(\.url)).subtracting(failed)
        files.removeAll { removed.contains($0.url) }
        selected = []
        message = Fmt.freedMessage(freed, failed: failed.count)
        working = false
    }
}
