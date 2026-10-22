import AppKit
import Foundation

/// Estado das proteções integradas do macOS (mostrado no Painel e na Análise Inteligente).
struct SecurityStatus {
    var sip: Bool?
    var gatekeeper: Bool?
    var firewall: Bool?
    var fileVault: Bool?
    var securityUpdates: Bool?
    var xprotectVersion: String?
    var checked: Date?

    struct Item: Identifiable {
        let id: String
        let title: String
        let detail: String
        let enabled: Bool?
        /// Painel das Definições onde se ativa (nil = não se ativa pelas Definições).
        let settingsURL: String?
        /// Explicação quando está desativado e não há painel para o ativar.
        let howToEnable: String?
    }

    var items: [Item] {
        [
            Item(id: "sip", title: "Proteção da integridade (SIP)",
                 detail: "Impede que programas alterem ficheiros do sistema.",
                 enabled: sip, settingsURL: nil,
                 howToEnable: "Só se ativa no modo de recuperação (Terminal ▸ csrutil enable)."),
            Item(id: "gatekeeper", title: "Gatekeeper",
                 detail: "Verifica as apps antes de as abrir.",
                 enabled: gatekeeper,
                 settingsURL: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Security",
                 howToEnable: nil),
            Item(id: "firewall", title: "Firewall",
                 detail: "Bloqueia ligações de entrada não autorizadas.",
                 enabled: firewall,
                 settingsURL: "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall",
                 howToEnable: nil),
            Item(id: "filevault", title: "FileVault",
                 detail: "Encripta o disco: protege os dados se o Mac for perdido ou roubado.",
                 enabled: fileVault,
                 settingsURL: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?FileVault",
                 howToEnable: nil),
            Item(id: "updates", title: "Atualizações de segurança",
                 detail: "Instala automaticamente correções de segurança e dados do sistema.",
                 enabled: securityUpdates,
                 settingsURL: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension",
                 howToEnable: nil),
        ]
    }

    var activeCount: Int { items.filter { $0.enabled == true }.count }
    var disabledCount: Int { items.filter { $0.enabled == false }.count }
}

enum SystemProtection {
    static func status() async -> SecurityStatus {
        async let sip = Shell.run("/usr/bin/csrutil", ["status"])
        async let gk = Shell.run("/usr/sbin/spctl", ["--status"])
        async let fw = Shell.run("/usr/libexec/ApplicationFirewall/socketfilterfw", ["--getglobalstate"])
        async let fv = Shell.run("/usr/bin/fdesetup", ["status"])
        let xp = NSDictionary(contentsOfFile: "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Info.plist")?["CFBundleShortVersionString"] as? String
        let (s, g, f, v) = await (sip, gk, fw, fv)
        return SecurityStatus(
            sip: s.out.isEmpty ? nil : s.out.contains("enabled"),
            gatekeeper: g.out.isEmpty ? nil : g.out.contains("enabled"),
            firewall: f.out.isEmpty ? nil : (f.out.contains("enabled") || f.out.contains("State = 1") || f.out.contains("State = 2")),
            fileVault: v.out.isEmpty ? nil : v.out.contains("On"),
            securityUpdates: securityUpdatesEnabled(),
            xprotectVersion: xp,
            checked: Date()
        )
    }

    /// "Instalar respostas de segurança e ficheiros do sistema" (ativo por defeito quando a chave não existe).
    private static func securityUpdatesEnabled() -> Bool {
        let prefs = NSDictionary(contentsOfFile: "/Library/Preferences/com.apple.SoftwareUpdate.plist")
        let critical = prefs?["CriticalUpdateInstall"] as? Bool ?? true
        let config = prefs?["ConfigDataInstall"] as? Bool ?? true
        return critical && config
    }

    static func openSettings(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}
