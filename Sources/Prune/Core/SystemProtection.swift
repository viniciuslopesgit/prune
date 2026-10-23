import AppKit

/// State of macOS's built-in protections (shown in the Dashboard and Smart Scan).
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
        /// Settings pane where it is turned on (nil = cannot be turned on in Settings).
        let settingsURL: String?
        /// Explanation when it is off and there is no pane to turn it on.
        let howToEnable: String?
    }

    var items: [Item] {
        [
            Item(id: "sip", title: String(localized: "System Integrity Protection (SIP)"),
                 detail: String(localized: "Prevents changes to system files."),
                 enabled: sip, settingsURL: nil,
                 howToEnable: String(localized: "Turn it on in recovery mode: Terminal ▸ csrutil enable.")),
            Item(id: "gatekeeper", title: "Gatekeeper",
                 detail: String(localized: "Checks apps before they open."),
                 enabled: gatekeeper,
                 settingsURL: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Security",
                 howToEnable: nil),
            Item(id: "firewall", title: "Firewall",
                 detail: String(localized: "Blocks unauthorized incoming connections."),
                 enabled: firewall,
                 settingsURL: "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall",
                 howToEnable: nil),
            Item(id: "filevault", title: "FileVault",
                 detail: String(localized: "Encrypts the disk. Protects your data if it is lost or stolen."),
                 enabled: fileVault,
                 settingsURL: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?FileVault",
                 howToEnable: nil),
            Item(id: "updates", title: String(localized: "Security updates"),
                 detail: String(localized: "Installs security fixes automatically."),
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

    /// "Install security responses and system files" (on by default when the key does not exist).
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
