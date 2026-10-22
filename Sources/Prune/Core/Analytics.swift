import Foundation

/// Estatísticas de utilização anónimas via Google Analytics 4 (Measurement Protocol).
///
/// - Só envia com o consentimento explícito do utilizador (Definições ▸ Geral, ou o pedido na barra lateral).
/// - Só envia nomes de eventos e valores agregados (módulo, número de itens, MB). Nunca caminhos,
///   nomes de ficheiros, nomes de apps ou qualquer dado do disco.
/// - O ID de medição e o segredo da API são injetados no Info.plist pelo `scripts/build_app.sh`
///   (variáveis GA_MEASUREMENT_ID e GA_API_SECRET, ou o ficheiro `analytics.env`, fora do git).
///   Um build sem eles nunca envia nada.
@MainActor
enum Analytics {
    private static let endpoint = "https://www.google-analytics.com/mp/collect"
    nonisolated static let clientIDKey = "analyticsClientID"
    /// Identifica a sessão (uma por arranque), para o GA4 contar utilizadores ativos.
    private static let sessionID = String(Int(Date().timeIntervalSince1970))

    private static var config: (measurementID: String, apiSecret: String)? {
        let info = Bundle.main.infoDictionary
        guard let id = info?["PruneGAMeasurementID"] as? String, !id.isEmpty,
              let secret = info?["PruneGAAPISecret"] as? String, !secret.isEmpty else { return nil }
        return (id, secret)
    }

    /// Texto que explica o que é enviado (Definições e pedido de consentimento).
    nonisolated static let disclosure = "Secções usadas, espaço libertado (só totais) e versões da app e do macOS, enviados para o Google Analytics. Nunca nomes de ficheiros, pastas ou apps."

    /// Há chaves neste build (sem elas, a opção nem aparece).
    static var isAvailable: Bool { config != nil }

    /// Ferramentas de diagnóstico (--selftest, --bench, --fdacheck) nunca enviam.
    private static var isToolRun: Bool {
        let args = CommandLine.arguments
        return ["--selftest", "--bench", "--fdacheck"].contains { args.contains($0) }
    }

    /// Identificador aleatório desta instalação. Criado só quando o utilizador aceita; apagado quando recusa.
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
        // Envio sem esperar resposta; falhas (sem rede, bloqueadores) são ignoradas.
        URLSession.shared.dataTask(with: req).resume()
    }

    /// Bytes em MB inteiros (valor agregado, sem detalhe dos ficheiros).
    static func mb(_ bytes: Int64) -> Int { Int(bytes / 1_000_000) }

    private static var cpuArch: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }
}
