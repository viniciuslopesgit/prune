import SwiftUI

struct SmartScanView: View {
    private var state: AppState { .shared }
    @ObservedObject private var model = AppState.shared.smartScan

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle:
                ModuleHeader(module: .smartScan)
                HeroView(
                    module: .smartScan,
                    headline: String(localized: "Welcome to Prune"),
                    message: String(localized: "Junk to clean and the state of macOS protections, in one click."),
                    features: [("externaldrive.badge.xmark", String(localized: "Caches, logs and Trash")),
                               ("checkmark.shield", String(localized: "State of macOS protections"))]
                ) {
                    Task { await model.scan() }
                }
            case .scanning:
                ScanningView(module: .smartScan, title: String(localized: "Scanning: \(model.step)"), detail: model.progressText)
            case .running:
                ScanningView(module: .smartScan, title: model.step, detail: model.progressText)
            case .results:
                ModuleHeader(module: .smartScan, subtitle: String(localized: "Scan complete"))
                results(model)
            case .done:
                DoneView(
                    module: .smartScan, title: String(localized: "Your Mac is in shape"),
                    message: summary(model),
                    failedCount: model.cleanReport.failed.count,
                    onBack: { model.phase = .idle }
                )
            }
        }
    }

    private func summary(_ m: SmartScanModel) -> String {
        var parts: [String] = []
        if m.runCleanup { parts.append(String(localized: "\(Fmt.bytes(m.cleanReport.freed)) of junk removed")) }
        return parts.isEmpty ? String(localized: "Nothing to do.") : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func results(_ model: SmartScanModel) -> some View {
        HStack(spacing: 16) {
            ResultCard(
                icon: "externaldrive.badge.xmark", title: String(localized: "Cleanup"),
                value: Fmt.bytes(model.junkSize), caption: model.junk.isEmpty ? String(localized: "Nothing to clean") : String(localized: "to clean"),
                enabled: $model.runCleanup,
                review: { state.selection = .systemJunk }
            )
            // Protection: information only (state of macOS protections), with no actions to run.
            ResultCard(
                icon: model.security.disabledCount == 0 ? "checkmark.shield" : "exclamationmark.shield", title: String(localized: "Protection"),
                value: model.security.disabledCount == 0 ? String(localized: "All on") : Fmt.count(model.security.disabledCount, String(localized: "protection off"), String(localized: "protections off")),
                caption: String(localized: "\(model.security.activeCount) of \(model.security.items.count) protections on"),
                enabled: nil,
                review: { state.selection = .dashboard }
            )
        }
        .padding(.horizontal, 32)
        .frame(maxHeight: .infinity)

        HStack(spacing: 14) {
            BigActionButton(title: String(localized: "Clean"), disabled: !model.runCleanup) {
                Task { await model.run() }
            }
            Button("Cancel") { model.phase = .idle }.buttonStyle(.bordered).controlSize(.large)
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
    /// nil = information-only card (no switch).
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
            Button("View details", action: review).buttonStyle(.bordered)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: 300)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
        .opacity(enabled?.wrappedValue == false ? 0.6 : 1)
    }
}
