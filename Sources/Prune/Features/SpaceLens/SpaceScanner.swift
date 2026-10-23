import Foundation

/// A node of the Space Lens tree. To save memory it only keeps the name:
/// the full path is rebuilt from the parents when needed.
final class DiskNode: Identifiable, Hashable {
    let name: String
    let isDirectory: Bool
    /// Aggregate node ("smaller items") — cannot be deleted or opened.
    let isAggregate: Bool
    var size: Int64
    var children: [DiskNode]
    weak var parent: DiskNode?
    /// Only the root keeps the URL.
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

/// Scans a folder and builds the size tree.
final class SpaceScanner: @unchecked Sendable {
    /// Folders smaller than this stay in the tree, but without their detailed contents.
    static let detailThreshold: Int64 = 1_000_000
    /// Maximum number of children kept per folder; the rest are aggregated.
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

    /// Each node is processed in its own autorelease pool: a folder's temporary URLs and attributes
    /// are freed as soon as it finishes, instead of at the end of the scan.
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
        // Does not cross into other mounted volumes.
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
        // Small folders do not justify keeping hundreds of nodes that will never be seen.
        let kept = total < Self.detailThreshold ? [] : Self.trim(children)
        return DiskNode(name: name, isDirectory: true, size: total, children: kept)
    }

    private func tick(_ url: URL) {
        lock.lock(); count += 1; let c = count; lock.unlock()
        if c % 500 == 0 { progress.report(String(localized: "\(c.formatted()) items scanned · \(url.deletingLastPathComponent().displayPath)")) }
    }

    /// Keeps the largest items; aggregates the rest into a single node.
    private static func trim(_ nodes: [DiskNode]) -> [DiskNode] {
        guard nodes.count > maxChildren else { return nodes.sorted { $0.size > $1.size } }
        let sorted = nodes.sorted { $0.size > $1.size }
        var result = Array(sorted.prefix(maxChildren))
        let rest = sorted.dropFirst(maxChildren)
        result.append(DiskNode(name: Fmt.count(rest.count, String(localized: "smaller item"), String(localized: "smaller items")), isDirectory: false,
                               size: rest.reduce(0) { $0 + $1.size }, isAggregate: true))
        return result
    }
}
