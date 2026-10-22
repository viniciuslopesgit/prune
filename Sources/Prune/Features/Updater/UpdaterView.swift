import SwiftUI

struct UpdaterView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var model = state.updater
        VStack(spacing: 0) {
            if model.checking {
                ScanningView(module: .updater, title: "A procurar atualizações…", detail: model.progressText)
            } else if !model.checked {
                ModuleHeader(module: .updater)
                HeroView(
                    module: .updater, headline: "Mantenha as apps atualizadas",
                    message: "Verifica as apps que se atualizam pelo site do programador (Sparkle) e os pacotes do Homebrew.",
                    features: [("globe", "Apps descarregadas da Internet"), ("mug", model.hasBrew ? "Apps e ferramentas do Homebrew" : "Homebrew (não instalado)"),
                               ("bag", "Atalho para atualizações da App Store")],
                    buttonTitle: "Verificar"
                ) { Task { await model.check() } }
            } else {
                ModuleHeader(module: .updater, subtitle: model.updates.isEmpty ? "Tudo atualizado" : "\(model.updates.count) atualização(ões) disponível(eis)") {
                    Button("App Store") { model.openAppStoreUpdates() }.buttonStyle(.bordered)
                    Button { Task { await model.check() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.bordered)
                }
                GlassPanel {
                    if model.updates.isEmpty {
                        EmptyStateView(icon: "checkmark.seal", title: "Todas as apps estão atualizadas",
                                       message: "As apps da App Store são atualizadas na própria App Store.")
                    } else {
                        List {
                            ForEach($model.updates) { $u in
                                HStack(spacing: 10) {
                                    CheckBox(state: u.selected) { u.selected.toggle() }
                                    if let app = u.appURL { FileIcon(url: app, size: 32) } else { Image(systemName: "shippingbox").font(.title2).frame(width: 32) }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(u.name).font(.headline)
                                        Text("\(u.current) → \(u.latest)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Pill(text: u.source.rawValue)
                                    if let notes = u.notesURL {
                                        Link("Novidades", destination: notes).font(.caption)
                                    }
                                }
                                .padding(.vertical, 3)
                                .listRowBackground(Color.clear)
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
                .padding(.horizontal, 32).padding(.bottom, 10)
                if !model.log.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading) { ForEach(model.log, id: \.self) { Text($0).font(.caption.monospaced()) } }
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 70).padding(.horizontal, 32)
                }
                ActionFooter(summary: "\(model.updates.filter(\.selected).count) selecionada(s)",
                             buttonTitle: model.installing ? "A atualizar…" : "Atualizar",
                             disabled: model.installing || !model.updates.contains(where: \.selected)) {
                    Task { await model.updateSelected() }
                }
            }
        }
    }
}
