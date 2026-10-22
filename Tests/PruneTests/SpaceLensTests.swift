import Foundation
import Testing
@testable import Prune

@Suite("Space Lens")
struct SpaceScannerTests {
    func scan(_ url: URL) -> DiskNode { SpaceScanner(progress: .silent).scan(url) }

    @Test("Each folder's size = sum of its children; children from largest to smallest")
    func treeSizes() throws {
        let tmp = try TempDir()
        try tmp.file("big/a", bytes: 2_000_000, fill: 1)
        try tmp.file("big/b", bytes: 1_000_000, fill: 1)
        try tmp.file("small", bytes: 10_000, fill: 1)
        try tmp.dir("empty")

        let root = scan(tmp.url)
        #expect(root.url == tmp.url)
        #expect(root.size == root.children.reduce(0) { $0 + $1.size })
        #expect(root.children.map(\.name) == ["big", "small", "empty"])
        let big = root.children[0]
        #expect(big.isDirectory)
        #expect(big.size == FS.size(of: tmp.path("big")))
        #expect(big.children.map(\.name) == ["a", "b"])
        #expect(big.children[0].url.path == tmp.path("big/a").path)
        #expect(big.children[0].path.map(\.name) == [tmp.url.lastPathComponent, "big", "a"])
    }

    @Test("Skips symbolic links (nothing is counted twice)")
    func skipsSymlinks() throws {
        let tmp = try TempDir()
        try tmp.file("real", bytes: 100_000, fill: 1)
        try tmp.symlink("link", to: tmp.path("real"))
        try tmp.symlink("cycle", to: tmp.url)
        let root = scan(tmp.url)
        #expect(root.children.map(\.name) == ["real"])
    }

    @Test("Small folders are kept without detail")
    func smallFoldersHaveNoChildren() throws {
        let tmp = try TempDir()
        try tmp.file("p/a", bytes: 1000, fill: 1)
        let p = try #require(scan(tmp.url).children.first)
        #expect(p.size > 0)
        #expect(p.children.isEmpty)
    }

    @Test("More than 50 items: the smallest are aggregated into a single node")
    func aggregatesSmallItems() throws {
        let tmp = try TempDir()
        for i in 0..<60 { try tmp.file("f\(i)", bytes: (i + 1) * 4096, fill: 1) }
        let root = scan(tmp.url)
        #expect(root.children.count == SpaceScanner.maxChildren + 1)
        let agg = try #require(root.children.last)
        #expect(agg.isAggregate)
        #expect(agg.name == "10 smaller items")
        #expect(agg.url == tmp.url, "the aggregate node does not point to any file")
        #expect(root.size == root.children.reduce(0) { $0 + $1.size })
        #expect(!root.children.dropLast().contains { $0.isAggregate })
    }
}

@Suite("Treemap")
struct TreemapTests {
    static let cases: [[Double]] = [
        [6, 6, 4, 3, 2, 2, 1], [1], [5, 5], [100, 1, 1, 1], (1...80).map(Double.init), [3, 0, 2],
    ]

    @Test("Fills the whole area, stays inside the rectangle and is proportional to size", arguments: cases)
    func fillsRect(sizes: [Double]) {
        let frame = CGRect(x: 10, y: 20, width: 600, height: 400)
        let rects = Treemap.layout(sizes: sizes, in: frame)
        #expect(rects.count == sizes.count)
        let area = rects.reduce(0.0) { $0 + Double($1.width * $1.height) }
        #expect(abs(area - 240_000) < 0.5)
        let total = sizes.reduce(0, +)
        for (r, s) in zip(rects, sizes) {
            #expect(r.minX >= frame.minX - 0.001 && r.maxX <= frame.maxX + 0.001)
            #expect(r.minY >= frame.minY - 0.001 && r.maxY <= frame.maxY + 0.001)
            #expect(abs(Double(r.width * r.height) - s / total * 240_000) < 0.5)
        }
    }

    @Test("The rectangles do not overlap")
    func noOverlap() {
        let rects = Treemap.layout(sizes: [9, 7, 5, 4, 3, 2, 2, 1, 1], in: CGRect(x: 0, y: 0, width: 300, height: 500))
        for i in rects.indices {
            for j in rects.indices where j > i {
                let o = rects[i].intersection(rects[j])
                #expect(o.isNull || o.width * o.height < 0.01)
            }
        }
    }

    @Test("Degenerate cases return empty rectangles")
    func degenerate() {
        #expect(Treemap.layout(sizes: [], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)
        #expect(Treemap.layout(sizes: [0, 0], in: CGRect(x: 0, y: 0, width: 10, height: 10)) == [.zero, .zero])
        #expect(Treemap.layout(sizes: [1, 2], in: .zero) == [.zero, .zero])
    }
}
