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
                    Text("Pode partilhar estatísticas anónimas de utilização. Ajudam a perceber que secções são úteis e o que corrigir.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                item("checkmark", Theme.leaf, "Que secções abre e quando faz uma análise ou limpeza")
                item("checkmark", Theme.leaf, "Totais: espaço encontrado e libertado, número de itens")
                item("checkmark", Theme.leaf, "Versão do Prune e do macOS")
                item("xmark", Theme.amber, "Nunca nomes de ficheiros, pastas, apps ou conteúdos")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Os dados são enviados para o Google Analytics. Pode mudar de ideias a qualquer momento em Definições ▸ Geral ▸ Estatísticas.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Não partilhar") { answer(false) }
                    .controlSize(.large)
                Button("Partilhar estatísticas") { answer(true) }
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
