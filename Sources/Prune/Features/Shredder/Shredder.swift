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
        if url.isDirectory && !url.isPackage || url.isPackage {
            if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [], errorHandler: { _, _ in true }) {
                FS.forEach(e) { f in
                    if !f.isDirectory { _ = overwrite(f, passes: passes) }
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

    private static func overwrite(_ url: URL, passes: Int) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.intValue,
              let h = try? FileHandle(forUpdating: url) else { return false }
        defer { try? h.close() }
        let chunk = 1_048_576
        var buffer = [UInt8](repeating: 0, count: chunk)
        for pass in 0..<max(1, passes) {
            try? h.seek(toOffset: 0)
            var written = 0
            while written < size {
                let n = min(chunk, size - written)
                if pass == passes - 1 || passes == 1 {
                    _ = SecRandomCopyBytes(kSecRandomDefault, n, &buffer)
                } else {
                    let byte: UInt8 = pass % 2 == 0 ? 0x00 : 0xFF
                    for i in 0..<n { buffer[i] = byte }
                }
                // Escreve diretamente a partir do buffer reutilizado (sem copiar para um Data novo).
                buffer.withUnsafeMutableBytes { raw in
                    autoreleasepool { h.write(Data(bytesNoCopy: raw.baseAddress!, count: n, deallocator: .none)) }
                }
                written += n
            }
            try? h.synchronize()
        }
        try? h.truncate(atOffset: 0)
        return true
    }
}
