import Foundation

/// An item that can be cleaned (file, folder or custom action).
struct CleanItem: Identifiable {
    let id = UUID()
    var url: URL
    var name: String
    var size: Int64
    var selected: Bool
    var detail: String?
    /// Alternative action to removal (e.g. clearing history in an SQLite database).
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
