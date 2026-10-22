import Foundation

enum Fmt {
    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    static func date(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "pt_PT")
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }

    static func relative(_ d: Date?) -> String {
        guard let d else { return "nunca" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "pt_PT")
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }

    static func percent(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }

    /// "1 item", "3 itens".
    static func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }
}
