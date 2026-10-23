import Foundation

enum MailAttachmentsScanner {
    static func scan(_ p: ProgressReporter) async -> [CleanCategory] {
        p.report(String(localized: "Scanning Mail downloads…"), force: true)
        var cats: [CleanCategory] = []

        let downloads = [
            URL.home("Library/Containers/com.apple.mail/Data/Library/Mail Downloads"),
            URL.home("Library/Mail Downloads"),
        ].flatMap { FS.childItems(of: $0, detail: String(localized: "Attachment opened from Mail")) }
        cats.append(CleanCategory(
            id: "mailDownloads", name: String(localized: "Opened attachments"), icon: "paperclip",
            info: String(localized: "Copies of attachments opened in Mail. The originals stay in the messages."),
            items: downloads
        ))

        p.report(String(localized: "Looking for attachments in mailboxes…"))
        var attachments = mailboxAttachments(p)
        attachments.sort { $0.size > $1.size }
        cats.append(CleanCategory(
            id: "mailAttachments", name: String(localized: "Attachments in messages"), icon: "envelope",
            info: String(localized: "Local copies. On IMAP, Exchange and iCloud accounts they stay on the server."),
            items: attachments,
            warning: Permissions.hasFullDiskAccess ? String(localized: "On POP accounts, removed attachments cannot be recovered.") : String(localized: "Grant Full Disk Access to scan Mail.")
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
                p.report(String(localized: "Scanning \(url.deletingLastPathComponent().lastPathComponent)…"))
                for msg in FS.children(url) {
                    for file in allFiles(in: msg) {
                        let size = FS.size(of: file)
                        guard size > 0 else { continue }
                        attachments.append(CleanItem(url: file, size: size, selected: false, detail: String(localized: "Local copy, recoverable from the server")))
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
