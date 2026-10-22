import SwiftUI

/// Assistente de Acesso Total ao Disco. Com esta permissão o macOS deixa de pedir autorização
/// pasta a pasta (Documentos, Secretária, Transferências, dados de outras apps, Mail, Safari…).
struct FullDiskAccessView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var state: Permissions.AccessState
    @State private var checking = false

    init(initialState: Permissions.AccessState = Permissions.hasFullDiskAccess ? .granted : .denied) {
        _state = State(initialValue: initialState)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 40))
                    .foregroundStyle(state == .denied ? Theme.amber : Theme.leaf)
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title2.bold())
                    Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }

            if state == .denied {
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Abra as Definições do Sistema no painel certo.") {
                        Button("Abrir Definições") { Permissions.openFullDiskAccessSettings() }
                    }
                    step(2, "Ative o Prune na lista. Se não aparecer, clique em \"+\" ou arraste a app para a lista.") {
                        Button("Mostrar a app no Finder") { FS.reveal(Bundle.main.bundleURL) }
                    }
                    step(3, "Volte aqui — a permissão é detetada automaticamente.") {
                        EmptyView()
                    }
                }
                .padding(14)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("O Prune usa esta permissão para analisar as pastas. Nada é apagado sem a sua confirmação.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                if state == .denied {
                    Button("Não voltar a mostrar") {
                        AppSettings.shared.fdaOnboardingDismissed = true
                        dismiss()
                    }
                    .buttonStyle(.borderless)
                }
                Spacer()
                switch state {
                case .granted:
                    Button("Continuar") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                case .needsRelaunch:
                    Button("Mais tarde") { dismiss() }
                    Button("Reabrir Prune") { Permissions.relaunch() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                case .denied:
                    Button("Agora não") { dismiss() }
                    Button(checking ? "A verificar…" : "Verificar") { Task { await refresh() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(26)
        .frame(width: 560)
        .task {
            // Deteta a permissão assim que o utilizador a concede.
            while state == .denied && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await refresh()
            }
        }
    }

    private var icon: String {
        switch state {
        case .granted: "checkmark.shield.fill"
        case .needsRelaunch: "arrow.clockwise.circle.fill"
        case .denied: "lock.shield"
        }
    }

    private var title: String {
        switch state {
        case .granted: "Acesso Total ao Disco ativo"
        case .needsRelaunch: "Permissão ativa — falta reabrir"
        case .denied: "Evite pedidos de autorização constantes"
        }
    }

    private var subtitle: String {
        switch state {
        case .granted: "O Prune já não vai pedir autorização para cada pasta."
        case .needsRelaunch: "O macOS já deu o Acesso Total ao Disco ao Prune, mas só o aplica depois de reabrir a app."
        case .denied: "Sem esta permissão, o macOS pergunta por cada pasta protegida que o Prune analisa."
        }
    }

    private func refresh() async {
        checking = true
        state = await Permissions.accessState()
        checking = false
    }

    private func step<A: View>(_ n: Int, _ text: String, @ViewBuilder action: () -> A) -> some View {
        let actionView = action()
        return HStack(alignment: .center, spacing: 12) {
            Text("\(n)").font(.headline).frame(width: 26, height: 26).foregroundStyle(Theme.onAccent).background(Theme.accent, in: Circle())
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            actionView.buttonStyle(.bordered)
        }
    }
}
