import SwiftUI

/// Pedido de consentimento para as estatísticas, mostrado uma vez no primeiro arranque.
/// Recusar é tão fácil como aceitar; a escolha pode ser mudada em Definições ▸ Geral ▸ Estatísticas.
struct AnalyticsConsentView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                LeafMark(size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ajudar a melhorar o Prune?").font(Theme.display(20))
                    Text("Partilhe estatísticas anónimas de utilização. Mostram-nos o que melhorar.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                item("checkmark", Theme.leaf, "Secções que usa, análises e limpezas")
                item("checkmark", Theme.leaf, "Totais de espaço encontrado e libertado")
                item("checkmark", Theme.leaf, "Versão do Prune e do macOS")
                item("xmark", Theme.amber, "Nunca nomes de ficheiros, pastas, apps ou conteúdos")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Enviado para o Google Analytics. Mude a qualquer momento em Definições ▸ Geral.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Não partilhar") { answer(false) }
                    .controlSize(.large)
                Button("Partilhar") { answer(true) }
                    .controlSize(.large)
            }
        }
        .padding(26)
        .frame(width: 500)
        .interactiveDismissDisabled()
    }

    private func item(_ icon: String, _ color: Color, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).font(.callout.bold()).foregroundStyle(color).frame(width: 18)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func answer(_ share: Bool) {
        AppSettings.shared.analyticsEnabled = share
        AppSettings.shared.analyticsAsked = true
        // O arranque desta sessão só conta a partir do consentimento.
        Analytics.track("app_open")
        dismiss()
    }
}
