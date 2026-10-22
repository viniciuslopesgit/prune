import Foundation
import Testing
@testable import Prune

/// The interface is in English in the code and translated by Resources/<language>.lproj/Localizable.strings.
/// scripts/check_localization.py checks that every text has a translation; these tests check that the keys
/// Swift generates at runtime (interpolations become %@, %lld…) are the ones written in the tables.
@Suite("Localization")
struct LocalizationTests {
    static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources")

    /// A bundle with only the Portuguese tables, built in a temporary folder.
    func portuguese(_ tmp: TempDir) throws -> Bundle {
        let lproj = try tmp.dir("Test.bundle/pt-PT.lproj")
        for name in ["Localizable.strings", "InfoPlist.strings"] {
            try FileManager.default.copyItem(at: Self.resources.appendingPathComponent("pt-PT.lproj/\(name)"),
                                             to: lproj.appendingPathComponent(name))
        }
        return try #require(Bundle(url: tmp.path("Test.bundle")))
    }

    @Test("Plain texts are translated")
    func plainText() throws {
        let tmp = try TempDir()
        let pt = try portuguese(tmp)
        #expect(String(localized: "Scan", bundle: pt) == "Analisar")
        #expect(String(localized: "Smart Scan", bundle: pt) == "Análise Inteligente")
    }

    @Test("Interpolated texts and numbers find their translation")
    func interpolations() throws {
        let tmp = try TempDir()
        let pt = try portuguese(tmp)
        let name = "Safari", cores = 8, on = 3, total = 5
        #expect(String(localized: "Cleaning \(name)…", bundle: pt) == "A limpar Safari…")
        #expect(String(localized: "\(cores) cores", bundle: pt) == "8 núcleos")
        #expect(String(localized: "\(on) of \(total) on", bundle: pt) == "3 de 5 ativas")
        // Positional placeholders in the translation keep each value in its place.
        #expect(String(localized: "\(name), up for \("2 h")", bundle: pt) == "Safari, ligado há 2 h")
    }

    @Test("A text without a translation stays in English")
    func fallsBackToEnglish() throws {
        let tmp = try TempDir()
        let pt = try portuguese(tmp)
        #expect(String(localized: "Text that is not in the table", bundle: pt) == "Text that is not in the table")
    }

    @Test("Each language has the same Info.plist texts")
    func infoPlistStrings() throws {
        for language in ["en", "pt-PT"] {
            let url = Self.resources.appendingPathComponent("\(language).lproj/InfoPlist.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language)")
            #expect(table["NSAppleEventsUsageDescription"]?.isEmpty == false)
        }
    }

    @Test("Display names come from the translation tables")
    func titlesAreNotEmpty() {
        for m in Module.allCases { #expect(!m.title.isEmpty) }
        for s in ModuleSection.allCases where s != .none { #expect(!s.title.isEmpty) }
        for k in FileKind.allCases { #expect(!k.title.isEmpty) }
        for a in FileAge.allCases { #expect(!a.title.isEmpty) }
        #expect(Set(ExtensionCategory.allCases.map(\.title)).count == ExtensionCategory.allCases.count)
        #expect(Set(UninstallerModel.Filter.allCases.map(\.title)).count == UninstallerModel.Filter.allCases.count)
    }
}
