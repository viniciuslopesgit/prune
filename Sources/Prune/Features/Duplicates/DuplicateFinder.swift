import CryptoKit
import Foundation
import Vision

struct DupFile: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let size: Int64
    let created: Date?
    let modified: Date?
}

struct DupGroup: Identifiable {
    let id = UUID()
    var files: [DupFile]
    let similar: Bool
    var size: Int64 { files.first?.size ?? 0 }
    var wasted: Int64 { files.dropFirst().reduce(0) { $0 + $1.size } }
}

enum DuplicateFinder {
    static func find(in roots: [URL], minSize: Int64, progress: ProgressReporter) -> [DupGroup] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey, .isSymbolicLinkKey]
        var bySize: [Int64: [DupFile]] = [:]
        var seen = Set<String>()
        var n = 0
        for root in roots {
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                                         errorHandler: { _, _ in true }) else { continue }
            let keySet = Set(keys)
            FS.forEach(e) { url in
                n += 1
                if n % 1000 == 0 { progress.report("A listar ficheiros… \(n.formatted())") }
                guard let rv = try? url.resourceValues(forKeys: keySet), rv.isRegularFile == true, rv.isSymbolicLink != true,
                      let size = rv.fileSize, Int64(size) >= minSize else { return true }
                guard seen.insert(url.resolvingSymlinksInPath().path).inserted else { return true }
                bySize[Int64(size), default: []].append(DupFile(url: url, size: Int64(size), created: rv.creationDate, modified: rv.contentModificationDate))
                return true
            }
        }
        seen = []
        let candidates = bySize.values.filter { $0.count > 1 }
        bySize = [:]
        // Um único buffer de leitura reutilizado para todos os ficheiros.
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: hashChunk, alignment: 16)
        defer { buffer.deallocate() }
        var groups: [DupGroup] = []
        var done = 0
        for files in candidates {
            done += 1
            progress.report("A comparar conteúdo… \(done)/\(candidates.count)")
            // 1.º passo: hash dos primeiros 64 KB; 2.º passo: hash completo.
            let partial = Dictionary(grouping: files) { hash($0.url, limit: 65_536, buffer: buffer) ?? UUID().uuidString }
            for (_, sub) in partial where sub.count > 1 {
                let full = sub.first!.size <= 65_536 ? ["": sub] : Dictionary(grouping: sub) { hash($0.url, limit: nil, buffer: buffer) ?? UUID().uuidString }
                for (_, same) in full where same.count > 1 {
                    // O mais antigo fica em primeiro lugar (é o que se mantém por defeito).
                    let sorted = same.sorted { ($0.created ?? .distantFuture) < ($1.created ?? .distantFuture) }
                    groups.append(DupGroup(files: sorted, similar: false))
                }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    static let hashChunk = 1_048_576

    /// SHA-256 do ficheiro (ou dos primeiros `limit` bytes), lido com `read(2)` para um buffer fixo:
    /// não cria objetos `Data` por bloco, por isso a memória não cresce com o tamanho dos ficheiros.
    static func hash(_ url: URL, limit: Int?, buffer: UnsafeMutableRawBufferPointer) -> String? {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)  // não encher a cache de ficheiros do sistema
        var hasher = SHA256()
        var total = 0
        while true {
            let want = min(buffer.count, limit.map { $0 - total } ?? buffer.count)
            guard want > 0 else { break }
            let n = read(fd, buffer.baseAddress, want)
            guard n > 0 else { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: buffer[0..<n]))
            total += n
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Resultado das fotografias semelhantes: os grupos e quantas imagens o Vision não conseguiu analisar
    /// (ficheiro danificado, formato não suportado, ou Vision indisponível neste Mac).
    struct SimilarPhotos {
        var groups: [DupGroup] = []
        var analysed = 0
        var unreadable = 0
        var firstError: String?
    }

    /// Fotografias semelhantes (não idênticas) com o Vision.
    static func similarPhotos(in roots: [URL], threshold: Float, progress: ProgressReporter) -> SimilarPhotos {
        let exts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "webp", "gif", "bmp"]
        var images: [DupFile] = []
        for root in roots {
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            FS.forEach(e) { url in
                guard exts.contains(url.pathExtension.lowercased()) else { return true }
                let rv = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
                images.append(DupFile(url: url, size: Int64(rv?.fileSize ?? 0), created: rv?.creationDate, modified: rv?.contentModificationDate))
                return images.count < 3000
            }
            if images.count >= 3000 { break }
        }
        var prints: [(DupFile, VNFeaturePrintObservation)] = []
        var result = SimilarPhotos()
        for (i, img) in images.enumerated() {
            progress.report("A analisar fotografias… \(i + 1)/\(images.count)")
            // Cada imagem é descodificada e libertada antes da seguinte.
            autoreleasepool {
                let req = VNGenerateImageFeaturePrintRequest()
                let handler = VNImageRequestHandler(url: img.url, options: [:])
                do {
                    try handler.perform([req])
                    if let obs = req.results?.first as? VNFeaturePrintObservation {
                        prints.append((img, obs))
                    } else {
                        result.unreadable += 1
                        result.firstError = result.firstError ?? "sem resultado do Vision"
                    }
                } catch {
                    result.unreadable += 1
                    result.firstError = result.firstError ?? error.localizedDescription
                }
            }
        }
        result.analysed = prints.count
        // Agrupa com union-find.
        var parent = Array(0..<prints.count)
        func find(_ x: Int) -> Int { var x = x; while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }; return x }
        for i in 0..<prints.count {
            if i % 50 == 0 { progress.report("A comparar fotografias… \(i)/\(prints.count)") }
            for j in (i + 1)..<prints.count {
                var d: Float = 0
                if (try? prints[i].1.computeDistance(&d, to: prints[j].1)) != nil, d < threshold {
                    parent[find(i)] = find(j)
                }
            }
        }
        var clusters: [Int: [DupFile]] = [:]
        for i in 0..<prints.count { clusters[find(i), default: []].append(prints[i].0) }
        result.groups = clusters.values.filter { $0.count > 1 }
            .map { DupGroup(files: $0.sorted { $0.size > $1.size }, similar: true) }
            .sorted { $0.files.count > $1.files.count }
        return result
    }
}
