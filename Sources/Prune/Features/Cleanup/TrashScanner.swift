import Foundation

enum TrashScanner {
    static func scan(_ p: ProgressReporter) async -> [CleanCategory] {
        p.report("A analisar o Lixo…", force: true)
        var cats = [CleanCategory(
            id: "userTrash", name: "Lixo do utilizador", icon: "trash",
            info: "Itens que moveu para o Lixo no disco de arranque.",
            items: FS.childItems(of: URL.home(".Trash"))
        )]
        let volumes = FS.children(URL(fileURLWithPath: "/Volumes")).filter { $0.resolvingSymlinksInPath().path != "/" }
        for vol in volumes {
            p.report("A analisar \(vol.lastPathComponent)…")
            let trash = vol.appendingPathComponent(".Trashes/\(Shell.uid)")
            let items = FS.childItems(of: trash)
            if !items.isEmpty {
                cats.append(CleanCategory(
                    id: "trash-\(vol.path)", name: "Lixo em \(vol.lastPathComponent)", icon: "externaldrive",
                    info: "Itens apagados no volume \(vol.lastPathComponent).", items: items
                ))
            }
        }
        return cats
    }
}
