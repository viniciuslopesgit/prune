import AppKit
import Foundation
import UniformTypeIdentifiers

let home = FileManager.default.homeDirectoryForCurrentUser

extension URL {
    static func home(_ path: String) -> URL { Prune.home.appendingPathComponent(path) }

    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    var isPackage: Bool {
        (try? resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
    }

    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    var displayPath: String {
        let h = Prune.home.path
        return path.hasPrefix(h) ? "~" + path.dropFirst(h.count) : path
    }

    var modificationDate: Date? {
        (try? resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

enum FS {
    static let sizeKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]

    /// Tamanho real em disco de um ficheiro ou pasta (recursivo).
    static func size(of url: URL) -> Int64 {
        guard let rv = try? url.resourceValues(forKeys: sizeKeys) else { return 0 }
        if rv.isSymbolicLink == true { return 0 }
        if rv.isDirectory != true {
            return Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        guard let e = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(sizeKeys), options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }
        forEach(e) { f in
            if let v = try? f.resourceValues(forKeys: sizeKeys), v.isDirectory != true {
                total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            }
            return true
        }
        return total
    }

    /// Percorre um enumerador esvaziando a autorelease pool a cada lote.
    /// Sem isto, em threads de fundo, cada URL visitado fica em memória até ao fim da análise.
    /// O corpo devolve `false` para parar.
    static func forEach(_ e: FileManager.DirectoryEnumerator, batch: Int = 256, _ body: (URL) -> Bool) {
        var finished = false
        while !finished {
            autoreleasepool {
                for _ in 0..<batch {
                    guard let url = e.nextObject() as? URL, body(url) else { finished = true; return }
                }
            }
        }
    }

    /// Calcula vários tamanhos em paralelo.
    static func sizes(of urls: [URL]) -> [Int64] {
        var result = [Int64](repeating: 0, count: urls.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: urls.count) { i in
            let s = size(of: urls[i])
            lock.lock(); result[i] = s; lock.unlock()
        }
        return result
    }

    static func children(_ url: URL, includeHidden: Bool = true) -> [URL] {
        let opts: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        return (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: opts
        )) ?? []
    }

    /// Itens filhos de uma pasta, com tamanho, prontos para limpeza.
    static func childItems(
        of dir: URL,
        selected: Bool = true,
        excluding: Set<String> = [],
        olderThan: Date? = nil,
        minSize: Int64 = 1,
        detail: String? = nil
    ) -> [CleanItem] {
        var urls = children(dir).filter { url in
            let name = url.lastPathComponent
            if name == ".DS_Store" || name == ".localized" { return false }
            if excluding.contains(where: { name.localizedCaseInsensitiveContains($0) }) { return false }
            if !SafetyGuard.canDelete(url) { return false }
            if let olderThan, let mod = url.modificationDate, mod > olderThan { return false }
            return true
        }
        urls.sort { $0.path < $1.path }
        let sizes = sizes(of: urls)
        return zip(urls, sizes)
            .filter { $0.1 >= minSize }
            .map { CleanItem(url: $0.0, size: $0.1, selected: selected, detail: detail) }
            .sorted { $0.size > $1.size }
    }

    /// Item único (pasta inteira) se existir.
    static func item(_ url: URL, selected: Bool = true, name: String? = nil, detail: String? = nil) -> CleanItem? {
        guard url.exists, SafetyGuard.canDelete(url) else { return nil }
        let s = size(of: url)
        guard s > 0 else { return nil }
        return CleanItem(url: url, name: name ?? url.lastPathComponent, size: s, selected: selected, detail: detail)
    }

    static func glob(_ base: URL, matching predicate: (String) -> Bool) -> [URL] {
        children(base).filter { predicate($0.lastPathComponent) }
    }

    private static let iconCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 400
        return c
    }()

    /// Ícone do Finder, em cache (evita criar um NSImage novo a cada redesenho).
    static func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache.setObject(icon, forKey: key)
        return icon
    }

    static func clearCaches() { iconCache.removeAllObjects() }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

enum Fmt {
    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    static func date(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_PT")
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }

    static func relative(_ d: Date?) -> String {
        guard let d else { return "nunca" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "pt_PT")
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }

    static func percent(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
}

/// Lê o Info.plist diretamente. `Bundle(url:)` guarda cada bundle numa cache global
/// que nunca é libertada — com centenas de apps isso são dezenas de MB.
enum BundleInfo {
    static func plist(_ app: URL) -> [String: Any]? {
        NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
    }

    static func identifier(_ app: URL) -> String? {
        plist(app)?["CFBundleIdentifier"] as? String
    }
}
