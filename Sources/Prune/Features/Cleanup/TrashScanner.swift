import Foundation

enum TrashScanner {
    static func scan(_ p: ProgressReporter) async -> [CleanCategory] {
        p.report(String(localized: "Scanning the Trash…"), force: true)
        var cats = [CleanCategory(
            id: "userTrash", name: String(localized: "User Trash"), icon: "trash",
            info: String(localized: "Items in the startup disk's Trash."),
            items: FS.childItems(of: URL.home(".Trash"))
        )]
        cats += volumeTrashes(in: URL(fileURLWithPath: "/Volumes"), uid: Shell.uid, progress: p)
        return cats
    }

    /// The current user's Trash on each mounted volume (`<volume>/.Trashes/<uid>`). The startup disk,
    /// which also shows up in /Volumes as a link to /, is skipped: its Trash is ~/.Trash.
    static func volumeTrashes(in volumes: URL, uid: uid_t, progress p: ProgressReporter = .silent) -> [CleanCategory] {
        var cats: [CleanCategory] = []
        for vol in FS.children(volumes).filter({ $0.resolvingSymlinksInPath().path != "/" }) {
            p.report(String(localized: "Scanning \(vol.lastPathComponent)…"))
            let items = FS.childItems(of: vol.appendingPathComponent(".Trashes/\(uid)"))
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
