import Foundation

enum Cleaner {
    /// Removes items. Those that fail because of permissions can then be retried with `retryAsAdmin`.
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
            // Folders with partially protected content: deletes what it can.
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

    /// Retries the removal with administrator privileges (asks for the password once).
    static func retryAsAdmin(_ urls: [URL], mode: DeleteMode) async -> CleanReport {
        let safe = urls.filter { SafetyGuard.canDelete($0) }
        guard !safe.isEmpty else { return CleanReport(failed: urls) }
        let sizes = FS.sizes(of: safe)
        let script: String
        if mode == .trash {
            // Moves to the user's Trash, keeping names unique.
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
