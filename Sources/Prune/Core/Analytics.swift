import Foundation

/// Anonymous usage statistics via Google Analytics 4 (Measurement Protocol).
///
/// - Only sends with the user's explicit consent (Settings ▸ General, or the prompt in the sidebar).
/// - Only sends event names and aggregate values (module, number of items, MB). Never paths,
///   file names, app names or any data from the disk.
/// - The measurement ID and API secret are injected into Info.plist by `scripts/build_app.sh`
///   (GA_MEASUREMENT_ID and GA_API_SECRET variables, or the `analytics.env` file, outside git).
///   A build without them never sends anything.
@MainActor
enum Analytics {
    private static let endpoint = "https://www.google-analytics.com/mp/collect"
    nonisolated static let clientIDKey = "analyticsClientID"
    /// Identifies the session (one per launch), so GA4 can count active users.
    private static let sessionID = String(Int(Date().timeIntervalSince1970))

    private static var config: (measurementID: String, apiSecret: String)? {
        let info = Bundle.main.infoDictionary
        guard let id = info?["PruneGAMeasurementID"] as? String, !id.isEmpty,
              let secret = info?["PruneGAAPISecret"] as? String, !secret.isEmpty else { return nil }
        return (id, secret)
    }

    /// Text explaining what is sent (Settings and consent prompt).
    nonisolated static let disclosure = String(localized: "Sections used, space freed (totals only) and app and macOS versions, sent to Google Analytics. Never names of files, folders or apps.")

    /// This build has keys (without them, the option does not even show).
    static var isAvailable: Bool { config != nil }

    /// Diagnostic tools (--selftest, --bench, --fdacheck) never send.
    private static var isToolRun: Bool {
        let args = CommandLine.arguments
        return ["--selftest", "--bench", "--fdacheck"].contains { args.contains($0) }
    }

    /// Random identifier of this installation. Created only when the user accepts; deleted when they decline.
    private static var clientID: String {
        if let id = UserDefaults.standard.string(forKey: clientIDKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: clientIDKey)
        return id
    }

    static func track(_ name: String, _ params: [String: Any] = [:]) {
        guard AppSettings.shared.analyticsEnabled, !isToolRun, let config else { return }
        var p = params
        p["session_id"] = sessionID
        p["engagement_time_msec"] = 100
        let info = Bundle.main.infoDictionary
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let body: [String: Any] = [
            "client_id": clientID,
            "non_personalized_ads": true,
            "user_properties": [
                "app_version": ["value": info?["CFBundleShortVersionString"] as? String ?? "?"],
                "macos_version": ["value": "\(os.majorVersion).\(os.minorVersion)"],
                "cpu_arch": ["value": cpuArch],
            ],
            "events": [["name": name, "params": p]],
        ]
        var comps = URLComponents(string: endpoint)!
        comps.queryItems = [URLQueryItem(name: "measurement_id", value: config.measurementID),
                            URLQueryItem(name: "api_secret", value: config.apiSecret)]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 10
        // Fire and forget; failures (no network, blockers) are ignored.
        URLSession.shared.dataTask(with: req).resume()
    }

    /// Bytes in whole MB (aggregate value, without file detail).
    static func mb(_ bytes: Int64) -> Int { Int(bytes / 1_000_000) }

    private static var cpuArch: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}
