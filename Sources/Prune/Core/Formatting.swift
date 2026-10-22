import Foundation

enum Fmt {
    /// Locale of the language the app is shown in (not the system region), so that dates and
    /// relative times match the rest of the interface.
    static var locale: Locale { Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en") }

    static func bytes(_ b: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    static func date(_ d: Date?, locale: Locale = Fmt.locale) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: d)
    }

    static func relative(_ d: Date?, locale: Locale = Fmt.locale) -> String {
        guard let d else { return String(localized: "never") }
        let f = RelativeDateTimeFormatter()
        f.locale = locale
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }

    static func percent(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }

    /// "1 item", "3 items".
    static func count(_ n: Int, _ one: String, _ many: String) -> String { "\(n) \(n == 1 ? one : many)" }

    /// "1 item", "3 items", in the interface language.
    static func items(_ n: Int) -> String { count(n, String(localized: "item"), String(localized: "items")) }

    /// "1 file", "3 files", in the interface language.
    static func files(_ n: Int) -> String { count(n, String(localized: "file"), String(localized: "files")) }

    /// "1.2 GB freed.", followed by how many files could not be removed, if any.
    static func freedMessage(_ freed: Int64, failed: Int) -> String {
        let summary = String(localized: "\(bytes(freed)) freed.")
        guard failed > 0 else { return summary }
        return summary + " " + count(failed, String(localized: "file was not removed"), String(localized: "files were not removed")) + "."
    }
}
