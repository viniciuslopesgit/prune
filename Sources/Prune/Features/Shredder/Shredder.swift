import Foundation
import Security

/// Shredder: overwrites the contents with random data before deleting.
///
/// Note: on SSDs and APFS volumes (copy-on-write, snapshots), the system may keep
/// old blocks out of the app's reach. The real protection on those disks is FileVault.
enum Shredder {
    static func shred(_ url: URL, passes: Int) async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: shredSync(url, passes: passes))
            }
        }
    }

    static func shredSync(_ url: URL, passes: Int) -> Bool {
        guard SafetyGuard.canDelete(url) else { return false }
        if isSymlink(url) {
            // A symbolic link is only removed: the target file is never overwritten.
            return (try? FileManager.default.removeItem(at: url)) != nil
        }
        if url.isDirectory {
            let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
            if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) {
                FS.forEach(e) { f in
                    let rv = try? f.resourceValues(forKeys: Set(keys))
                    if rv?.isRegularFile == true, rv?.isSymbolicLink != true { _ = overwrite(f, passes: passes) }
                    return true
                }
            }
        } else {
            guard overwrite(url, passes: passes) else { return false }
        }
        // Renames before deleting, so the original name is not left in the metadata.
        let renamed = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        let target = (try? FileManager.default.moveItem(at: url, to: renamed)) != nil ? renamed : url
        return (try? FileManager.default.removeItem(at: target)) != nil
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

    /// Overwrites the contents: alternating 0x00/0xFF passes, the last one with random data.
    private static func overwrite(_ url: URL, passes: Int) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.intValue,
              let handle = try? FileHandle(forUpdating: url) else { return false }
        defer { try? handle.close() }
        let passes = max(1, passes)
        let chunk = 1_048_576
        var buffer = [UInt8](repeating: 0, count: chunk)
        do {
            for pass in 0..<passes {
                try handle.seek(toOffset: 0)
                var written = 0
                while written < size {
                    let n = min(chunk, size - written)
                    if pass == passes - 1 {
                        _ = SecRandomCopyBytes(kSecRandomDefault, n, &buffer)
                    } else {
                        buffer.withUnsafeMutableBufferPointer { $0.update(repeating: pass % 2 == 0 ? 0x00 : 0xFF) }
                    }
                    // Writes from the reused buffer, without copying into a new Data.
                    try buffer.withUnsafeBytes { raw in
                        try autoreleasepool {
                            try handle.write(contentsOf: Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: raw.baseAddress!), count: n, deallocator: .none))
                        }
                    }
                    written += n
                }
                try handle.synchronize()
            }
            try handle.truncate(atOffset: 0)
            return true
        } catch {
            return false
        }
    }
}
