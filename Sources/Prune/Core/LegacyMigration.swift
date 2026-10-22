import Foundation

/// A app chamava-se MaCClear (identificador `app.maclear.MaCClear`). Com o identificador novo, o macOS
/// trata-a como outra app: aqui copiam-se uma vez as definições antigas (exclusões, modos de remoção,
/// consentimento das estatísticas…). As permissões do macOS (Acesso Total ao Disco) não se copiam:
/// o utilizador tem de as voltar a conceder, por isso o assistente volta a aparecer.
enum LegacyMigration {
    static let legacyBundleID = "app.maclear.MaCClear"
    private static let doneKey = "migratedFromLegacyBundleID"

    /// Idempotente; corre antes de qualquer leitura das definições.
    static func run() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: doneKey) else { return }
        defer { d.set(true, forKey: doneKey) }
        let domain = legacyBundleID as CFString
        guard let keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String],
              !keys.isEmpty,
              let old = CFPreferencesCopyMultiple(keys as CFArray, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any]
        else { return }
        for (key, value) in old where d.object(forKey: key) == nil {
            d.set(value, forKey: key)
        }
        // A permissão não passa para o identificador novo: mostrar o assistente outra vez.
        d.set(false, forKey: "fdaOnboardingDismissed")
    }
}
