import Foundation
import Security

/// Destruidor: sobrescreve o conteúdo com dados aleatórios antes de apagar.
///
/// Nota: em SSDs e volumes APFS (cópia-em-escrita, instantâneos), o sistema pode manter
/// blocos antigos fora do alcance da app. A proteção real nesses discos é o FileVault.
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
            // Uma ligação simbólica só é removida: o ficheiro de destino nunca é sobrescrito.
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
        // Renomeia antes de apagar, para não deixar o nome original nos metadados.
        let renamed = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        let target = (try? FileManager.default.moveItem(at: url, to: renamed)) != nil ? renamed : url
        return (try? FileManager.default.removeItem(at: target)) != nil
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

    /// Sobrescreve o conteúdo: passagens alternadas de 0x00/0xFF e a última com dados aleatórios.
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
                    // Escreve a partir do buffer reutilizado, sem copiar para um Data novo.
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
