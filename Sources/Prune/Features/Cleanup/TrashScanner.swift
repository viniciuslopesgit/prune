import Foundation

enum TrashScanner {
    static func scan(_ p: ProgressReporter) async -> [CleanCategory] {
        p.report(String(localized: "Scanning the Trash…"), force: true)
        var cats = [CleanCategory(
            id: "userTrash", name: String(localized: "User Trash"), icon: "trash",
            info: String(localized: "Items in the startup disk's Trash."),
            items: FS.childItems(of: URL.home(".Trash"))
        )]
        let volumes = FS.children(URL(fileURLWithPath: "/Volumes")).filter { $0.resolvingSymlinksInPath().path != "/" }
        for vol in volumes {
            p.report(String(localized: "Scanning \(vol.lastPathComponent)…"))
            let trash = vol.appendingPathComponent(".Trashes/\(Shell.uid)")
            let items = FS.childItems(of: trash)
            if !items.isEmpty {
                cats.append(CleanCategory(
                    id: "trash-\(vol.path)", name: String(localized: "Trash on \(vol.lastPathComponent)"), icon: "externaldrive",
                    info: String(localized: "Items deleted on the \(vol.lastPathComponent) volume."), items: items
                ))
            }
        }
        return cats
    }
}
