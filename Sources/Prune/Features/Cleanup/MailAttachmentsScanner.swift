import Foundation

enum MailAttachmentsScanner {
    static func scan(_ p: ProgressReporter) async -> [CleanCategory] {
        p.report("A analisar transferências do Mail…", force: true)
        var cats: [CleanCategory] = []

        let downloads = [
            URL.home("Library/Containers/com.apple.mail/Data/Library/Mail Downloads"),
            URL.home("Library/Mail Downloads"),
        ].flatMap { FS.childItems(of: $0, detail: "Anexo aberto a partir do Mail") }
        cats.append(CleanCategory(
            id: "mailDownloads", name: "Anexos abertos", icon: "paperclip",
            info: "Cópias de anexos abertos no Mail. Os originais ficam nas mensagens.",
            items: downloads
        ))

        p.report("A procurar anexos nas caixas de correio…")
        var attachments = mailboxAttachments(p)
        attachments.sort { $0.size > $1.size }
        cats.append(CleanCategory(
            id: "mailAttachments", name: "Anexos nas mensagens", icon: "envelope",
            info: "Cópias locais. Em contas IMAP, Exchange e iCloud ficam no servidor.",
            items: attachments,
            warning: Permissions.hasFullDiskAccess ? "Em contas POP, os anexos removidos não se recuperam." : "Conceda Acesso Total ao Disco para analisar o Mail."
        ))
        return cats
    }


    private static func mailboxAttachments(_ p: ProgressReporter) -> [CleanItem] {
        var attachments: [CleanItem] = []
        let mailRoot = URL.home("Library/Mail")
        for version in FS.children(mailRoot) where version.lastPathComponent.hasPrefix("V") {
            guard let e = FileManager.default.enumerator(
                at: version, includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles], errorHandler: { _, _ in true }
            ) else { continue }
            FS.forEach(e) { url in
                guard url.lastPathComponent == "Attachments", url.isDirectory else { return true }
                e.skipDescendants()
                p.report("A analisar \(url.deletingLastPathComponent().lastPathComponent)…")
                for msg in FS.children(url) {
                    for file in allFiles(in: msg) {
                        let size = FS.size(of: file)
                        guard size > 0 else { continue }
                        attachments.append(CleanItem(url: file, size: size, selected: false, detail: "Cópia local, recuperável a partir do servidor"))
                    }
                }
                return true
            }
        }
        return attachments
    }

    private static func allFiles(in dir: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles], errorHandler: { _, _ in true }) else { return [] }
        var files: [URL] = []
        FS.forEach(e) { url in
            if !url.isDirectory { files.append(url) }
            return true
        }
        return files
    }
}
