import Foundation
import Observation

/// Um item que pode ser limpo (ficheiro, pasta ou ação personalizada).
struct CleanItem: Identifiable {
    let id = UUID()
    var url: URL
    var name: String
    var size: Int64
    var selected: Bool
    var detail: String?
    /// Ação alternativa à remoção (ex.: limpar histórico numa base SQLite).
    var customAction: (@Sendable () async -> Bool)?

    init(url: URL, name: String? = nil, size: Int64, selected: Bool = true, detail: String? = nil,
         customAction: (@Sendable () async -> Bool)? = nil) {
        self.url = url
        self.name = name ?? url.lastPathComponent
        self.size = size
        self.selected = selected
        self.detail = detail
        self.customAction = customAction
    }
}

struct CleanCategory: Identifiable {
    let id: String
    var name: String
    var icon: String
    var info: String
    var items: [CleanItem]
    var warning: String?

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.filter(\.selected).reduce(0) { $0 + $1.size } }
    var selectedCount: Int { items.filter(\.selected).count }
    var allSelected: Bool { !items.isEmpty && items.allSatisfy(\.selected) }
    var noneSelected: Bool { items.allSatisfy { !$0.selected } }
}

struct CleanReport {
    var freed: Int64 = 0
    var removed = 0
    var failed: [URL] = []

    mutating func merge(_ o: CleanReport) {
        freed += o.freed
        removed += o.removed
        failed += o.failed
    }
}

enum Cleaner {
    /// Remove itens. Os que falham por permissões podem depois ser repetidos com `retryAsAdmin`.
    static func remove(_ items: [CleanItem], mode: DeleteMode) async -> CleanReport {
        var report = CleanReport()
        for item in items {
            if let action = item.customAction {
                if await action() {
                    report.freed += item.size
                    report.removed += 1
                } else {
                    report.failed.append(item.url)
                }
                continue
            }
            if removeSync(item.url, mode: mode) {
                report.freed += item.size
                report.removed += 1
            } else {
                report.failed.append(item.url)
            }
        }
        return report
    }

    static func remove(urls: [URL], mode: DeleteMode) async -> CleanReport {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                var r = CleanReport()
                for url in urls {
                    let size = FS.size(of: url)
                    if removeSync(url, mode: mode) {
                        r.freed += size
                        r.removed += 1
                    } else {
                        r.failed.append(url)
                    }
                }
                cont.resume(returning: r)
            }
        }
    }

    static func removeSync(_ url: URL, mode: DeleteMode) -> Bool {
        guard SafetyGuard.canDelete(url) else { return false }
        guard FileManager.default.fileExists(atPath: url.path) || isBrokenSymlink(url) else { return true }
        do {
            switch mode {
            case .trash: try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            case .permanent: try FileManager.default.removeItem(at: url)
            }
            return true
        } catch {
            // Pastas com conteúdo parcialmente protegido: apaga o que for possível.
            if mode == .permanent, url.isDirectory {
                for child in FS.children(url) { _ = removeSync(child, mode: .permanent) }
                return (try? FileManager.default.removeItem(at: url)) != nil
            }
            return false
        }
    }

    private static func isBrokenSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// Repete a remoção com privilégios de administrador (pede a palavra-passe uma vez).
    static func retryAsAdmin(_ urls: [URL], mode: DeleteMode) async -> CleanReport {
        let safe = urls.filter { SafetyGuard.canDelete($0) }
        guard !safe.isEmpty else { return CleanReport(failed: urls) }
        let sizes = FS.sizes(of: safe)
        let script: String
        if mode == .trash {
            // Move para o Lixo do utilizador, mantendo nomes únicos.
            let trash = home.appendingPathComponent(".Trash").path
            script = safe.map { url in
                let dest = trash + "/" + url.lastPathComponent + " " + String(UUID().uuidString.prefix(6))
                return "mv -f \(Shell.quote(url.path)) \(Shell.quote(dest)) && chown -R \(Shell.uid) \(Shell.quote(dest))"
            }.joined(separator: "; ")
        } else {
            script = "rm -rf " + safe.map { Shell.quote($0.path) }.joined(separator: " ")
        }
        _ = await Shell.admin(script)
        var r = CleanReport()
        for (url, size) in zip(safe, sizes) {
            if url.exists { r.failed.append(url) } else { r.freed += size; r.removed += 1 }
        }
        return r
    }
}

/// Envia mensagens de progresso para a interface sem a sobrecarregar.
final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var last = Date.distantPast
    private let handler: @MainActor (String) -> Void

    init(_ handler: @escaping @MainActor (String) -> Void) { self.handler = handler }

    func report(_ text: String, force: Bool = false) {
        lock.lock()
        let now = Date()
        guard force || now.timeIntervalSince(last) > 0.08 else { lock.unlock(); return }
        last = now
        lock.unlock()
        Task { @MainActor in handler(text) }
    }

    static let silent = ProgressReporter { _ in }
}

extension Task where Success == Never, Failure == Never {
    static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
