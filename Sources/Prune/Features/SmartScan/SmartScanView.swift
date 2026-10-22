import SwiftUI

struct SmartScanView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let model = state.smartScan
        VStack(spacing: 0) {
            switch model.phase {
            case .idle:
                ModuleHeader(module: .smartScan)
                HeroView(
                    module: .smartScan,
                    headline: "Bem-vindo ao Prune",
                    message: "Lixo para limpar e estado das proteções do macOS, num clique.",
                    features: [("externaldrive.badge.xmark", "Caches, registos e Lixo"),
                               ("checkmark.shield", "Estado das proteções do macOS")]
                ) {
                    Task { await model.scan() }
                }
            case .scanning:
                ScanningView(module: .smartScan, title: "A analisar: \(model.step)", detail: model.progressText)
            case .running:
                ScanningView(module: .smartScan, title: model.step, detail: model.progressText)
            case .results:
                ModuleHeader(module: .smartScan, subtitle: "Análise concluída")
                results(model)
            case .done:
                DoneView(
                    module: .smartScan, title: "O seu Mac está em forma",
                    message: summary(model),
                    failedCount: model.cleanReport.failed.count,
                    onBack: { model.phase = .idle }
                )
            }
        }
    }

    private func summary(_ m: SmartScanModel) -> String {
        var parts: [String] = []
        if m.runCleanup { parts.append("\(Fmt.bytes(m.cleanReport.freed)) de lixo removido") }
        return parts.isEmpty ? "Nada a fazer." : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func results(_ model: SmartScanModel) -> some View {
        @Bindable var model = model
        HStack(spacing: 16) {
            ResultCard(
                icon: "externaldrive.badge.xmark", title: "Limpeza",
                value: Fmt.bytes(model.junkSize), caption: model.junk.isEmpty ? "Nada a limpar" : "para limpar",
                enabled: $model.runCleanup,
                review: { state.selection = .systemJunk }
            )
            // Proteção: só informação (estado das proteções do macOS), sem ações a executar.
            ResultCard(
                icon: model.security.disabledCount == 0 ? "checkmark.shield" : "exclamationmark.shield", title: "Proteção",
                value: model.security.disabledCount == 0 ? "Tudo ativo" : "\(Fmt.count(model.security.disabledCount, "desativada", "desativadas"))",
                caption: "\(model.security.activeCount) de \(model.security.items.count) proteções ativas",
                enabled: nil,
                review: { state.selection = .dashboard }
            )
        }
        .padding(.horizontal, 32)
        .frame(maxHeight: .infinity)

        HStack(spacing: 14) {
            BigActionButton(title: "Limpar", disabled: !model.runCleanup) {
                Task { await model.run() }
            }
            Button("Cancelar") { model.phase = .idle }.buttonStyle(.bordered).controlSize(.large)
            Spacer()
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }
}

private struct ResultCard: View {
    let icon: String
    let title: String
    let value: String
    let caption: String
    /// nil = cartão só informativo (sem interruptor).
    var enabled: Binding<Bool>?
    let review: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: icon).font(.title2).foregroundStyle(Theme.accent)
                Text(title).font(.headline)
                Spacer()
                if let enabled { Toggle("", isOn: enabled).toggleStyle(.switch).labelsHidden() }
            }
            Spacer()
            Text(value).font(Theme.display(38)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
            Text(caption).foregroundStyle(.secondary)
            Button("Ver detalhes", action: review).buttonStyle(.bordered)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 300)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
        .opacity(enabled?.wrappedValue == false ? 0.6 : 1)
    }
}
