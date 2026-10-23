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
        _ = await Shell.admin(adminScript(safe, mode: mode))
        var r = CleanReport()
        for (url, size) in zip(safe, sizes) {
            if url.exists { r.failed.append(url) } else { r.freed += size; r.removed += 1 }
        }
        return r
    }

    /// The script `retryAsAdmin` runs as root, one subshell per item.
    ///
    /// Root must not follow a link that someone puts in place after `SafetyGuard` checked the path:
    /// each subshell enters the item's real parent folder (`cd -P`), confirms it is still the folder that
    /// was checked and only then acts on `./name`. From then on the folder is held by the shell itself,
    /// so swapping one of its parents for a link changes nothing. The item itself is never followed:
    /// `rm -r` and `mv` act on a link, not on its target, and `chown -h` likewise.
    /// Items whose parent cannot be resolved, or that the guard refuses once resolved, are left out.
    static func adminScript(_ urls: [URL], mode: DeleteMode,
                            trash: URL = home.appendingPathComponent(".Trash"), uid: uid_t = Shell.uid) -> String {
        let trashPath = SafetyGuard.realPath(trash.path) ?? trash.path
        return urls.compactMap { url -> String? in
            let name = url.lastPathComponent
            guard !name.isEmpty, name != ".", name != "..",
                  let parent = SafetyGuard.realPath(url.deletingLastPathComponent().path),
                  SafetyGuard.canDelete(URL(fileURLWithPath: parent).appendingPathComponent(name)) else { return nil }
            let enter = "cd -P -- \(Shell.quote(parent)) && [ \"$(pwd -P)\" = \(Shell.quote(parent)) ]"
            let item = Shell.quote("./" + name)
            switch mode {
            case .permanent:
                return "(\(enter) && /bin/rm -rf -- \(item))"
            case .trash:
                // Moves to the user's Trash (a real folder, not a link), keeping names unique.
                let dest = Shell.quote(trashPath + "/" + name + " " + String(UUID().uuidString.prefix(6)))
                let trashOK = "[ -d \(Shell.quote(trashPath)) ] && [ ! -L \(Shell.quote(trashPath)) ]"
                return "(\(enter) && \(trashOK) && /bin/mv -- \(item) \(dest) && /usr/sbin/chown -hR \(uid) \(dest))"
            }
        }.joined(separator: "; ")
    }
}
