import Foundation

/// Nó da árvore da Lente de Espaço. Para poupar memória guarda só o nome:
/// o caminho completo é reconstruído a partir dos pais quando é preciso.
final class DiskNode: Identifiable, Hashable {
    let name: String
    let isDirectory: Bool
    /// Nó agregado ("itens mais pequenos") — não pode ser apagado nem aberto.
    let isAggregate: Bool
    var size: Int64
    var children: [DiskNode]
    weak var parent: DiskNode?
    /// Só a raiz guarda o URL.
    private let rootURL: URL?

    init(name: String, isDirectory: Bool, size: Int64, children: [DiskNode] = [], isAggregate: Bool = false, rootURL: URL? = nil) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.children = children
        self.isAggregate = isAggregate
        self.rootURL = rootURL
        for c in children { c.parent = self }
    }

    var id: ObjectIdentifier { ObjectIdentifier(self) }

    var url: URL {
        if let rootURL { return rootURL }
        guard let parent else { return URL(fileURLWithPath: name) }
        return isAggregate ? parent.url : parent.url.appendingPathComponent(name, isDirectory: isDirectory)
    }

    static func == (a: DiskNode, b: DiskNode) -> Bool { a === b }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }

    var path: [DiskNode] {
        var p: [DiskNode] = [self]
        var cur = parent
        while let c = cur { p.insert(c, at: 0); cur = c.parent }
        return p
    }
}

/// Analisa uma pasta e constrói a árvore de tamanhos.
final class SpaceScanner: @unchecked Sendable {
    /// Pastas mais pequenas do que isto ficam na árvore, mas sem o conteúdo detalhado.
    static let detailThreshold: Int64 = 1_000_000
    /// Número máximo de filhos guardados por pasta; os restantes são agregados.
    static let maxChildren = 50

    private let progress: ProgressReporter
    private let lock = NSLock()
    private var count = 0
    private let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .volumeIdentifierKey]
    private lazy var keySet = Set(keys)
    private var rootVolume: NSObject?
    var cancelled = false

    init(progress: ProgressReporter) { self.progress = progress }

    func scan(_ url: URL) -> DiskNode {
        rootVolume = (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        _ = keySet
        let entries = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])) ?? []
        var nodes = [DiskNode?](repeating: nil, count: entries.count)
        DispatchQueue.concurrentPerform(iterations: entries.count) { i in
            let n = self.node(for: entries[i])
            self.lock.lock(); nodes[i] = n; self.lock.unlock()
        }
        let children = nodes.compactMap { $0 }
        return DiskNode(name: url.lastPathComponent, isDirectory: true, size: children.reduce(0) { $0 + $1.size },
                        children: Self.trim(children), rootURL: url)
    }

    /// Cada nó é processado na sua própria autorelease pool: os URLs e atributos temporários
    /// de uma pasta são libertados assim que ela termina, em vez de no fim da análise.
    private func node(for url: URL) -> DiskNode? {
        autoreleasepool { makeNode(url) }
    }

    private func makeNode(_ url: URL) -> DiskNode? {
        if cancelled { return nil }
        guard let rv = try? url.resourceValues(forKeys: keySet) else { return nil }
        if rv.isSymbolicLink == true { return nil }
        let name = url.lastPathComponent
        if rv.isDirectory != true {
            tick(url)
            return DiskNode(name: name, isDirectory: false, size: Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0))
        }
        // Não atravessa outros volumes montados.
        if let v = rv.volumeIdentifier as? NSObject, let root = rootVolume, !v.isEqual(root) { return nil }
        if url.path == "/System/Volumes" || url.path == "/Volumes" { return nil }
        if rv.isPackage == true {
            tick(url)
            return DiskNode(name: name, isDirectory: false, size: FS.size(of: url))
        }
        let entries = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [])) ?? []
        var children: [DiskNode] = []
        children.reserveCapacity(entries.count)
        for e in entries {
            if let n = node(for: e) { children.append(n) }
        }
        let total = children.reduce(0) { $0 + $1.size }
        // Pastas pequenas não justificam guardar centenas de nós que nunca serão vistos.
        let kept = total < Self.detailThreshold ? [] : Self.trim(children)
        return DiskNode(name: name, isDirectory: true, size: total, children: kept)
    }

    private func tick(_ url: URL) {
        lock.lock(); count += 1; let c = count; lock.unlock()
        if c % 500 == 0 { progress.report("\(c.formatted()) itens analisados · \(url.deletingLastPathComponent().displayPath)") }
    }

    /// Mantém os maiores itens; agrega os restantes num só nó.
    private static func trim(_ nodes: [DiskNode]) -> [DiskNode] {
        guard nodes.count > maxChildren else { return nodes.sorted { $0.size > $1.size } }
        let sorted = nodes.sorted { $0.size > $1.size }
        var result = Array(sorted.prefix(maxChildren))
        let rest = sorted.dropFirst(maxChildren)
        result.append(DiskNode(name: "\(rest.count) itens mais pequenos", isDirectory: false,
                               size: rest.reduce(0) { $0 + $1.size }, isAggregate: true))
        return result
    }
}
