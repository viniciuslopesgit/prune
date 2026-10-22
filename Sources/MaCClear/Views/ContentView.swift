import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var access: Permissions.AccessState = Permissions.hasFullDiskAccess ? .granted : .denied
    @State private var showFDA = false

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(selection: $state.selection) {
                ForEach(ModuleSection.allCases, id: \.self) { section in
                    let modules = Module.allCases.filter { $0.section == section }
                    if section == .none {
                        ForEach(modules) { row($0) }
                    } else {
                        Section(section.rawValue) {
                            ForEach(modules) { row($0) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 260)
            .safeAreaInset(edge: .bottom) {
                if access == .granted && Analytics.isAvailable && !AppSettings.shared.analyticsAsked {
                    analyticsPrompt
                }
                if access != .granted {
                    Button {
                        showFDA = true
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: access == .needsRelaunch ? "arrow.clockwise.circle" : "lock.open.trianglebadge.exclamationmark")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(access == .needsRelaunch ? "Reabra o Prune" : "Acesso Total ao Disco").font(.caption.bold())
                                Text(access == .needsRelaunch
                                     ? "A permissão já está ativa; o macOS aplica-a ao reabrir a app."
                                     : "Necessário para analisar Safari, Mail e outras pastas protegidas.").font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.amber.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                }
            }
        } detail: {
            // Fixa o conteúdo ao tamanho real da coluna (o fundo não deve ditar a altura).
            GeometryReader { geo in
                detail(for: state.selection)
                    .id(state.selection)
                    .transition(.opacity)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
            .background(ModuleBackground(module: state.selection))
            .animation(.easeInOut(duration: 0.25), value: state.selection)
            .onChange(of: state.selection) { _, m in Analytics.track("module_view", ["module": m.rawValue]) }
        }
        .sheet(isPresented: $showFDA, onDismiss: { Task { access = await Permissions.accessState() } }) {
            FullDiskAccessView(initialState: access)
        }
        .task { await checkAccessAtLaunch() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { access = await Permissions.accessState() }
        }
    }

    /// Logo a seguir a uma atualização, o macOS pode ainda não reconhecer a app nova durante um
    /// instante. Por isso volta a verificar durante alguns segundos antes de mostrar o assistente,
    /// e distingue "sem permissão" de "permissão ativa mas a app tem de ser reaberta".
    private func checkAccessAtLaunch() async {
        var inProcess = Permissions.hasFullDiskAccess
        for _ in 0..<6 where !inProcess {
            try? await Task.sleep(nanoseconds: 500_000_000)
            inProcess = Permissions.hasFullDiskAccess
        }
        access = inProcess ? .granted : (await Permissions.hasFullDiskAccessFresh() ? .needsRelaunch : .denied)
        Permissions.log("arranque: acesso=\(access) versão=\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")")
        switch access {
        case .granted: break
        case .needsRelaunch: showFDA = true
        case .denied: showFDA = !AppSettings.shared.fdaOnboardingDismissed
        }
    }

    private var analyticsPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ajudar a melhorar o Prune?").font(.caption.bold())
            Text("Partilhe estatísticas anónimas: que secções usa e quanto espaço liberta. Nunca nomes de ficheiros.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Partilhar") { answerAnalytics(true) }.buttonStyle(.borderedProminent).tint(Theme.leaf)
                Button("Agora não") { answerAnalytics(false) }.buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.leaf.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(10)
    }

    private func answerAnalytics(_ yes: Bool) {
        AppSettings.shared.analyticsEnabled = yes
        AppSettings.shared.analyticsAsked = true
        Analytics.track("app_open")
    }

    private func row(_ m: Module) -> some View {
        Label {
            HStack {
                Text(m.title)
                Spacer()
                badge(for: m)
            }
        } icon: {
            Image(systemName: m.icon)
        }
        .tag(m)
    }

    @ViewBuilder
    private func badge(for m: Module) -> some View {
        switch m {
        case .systemJunk where state.systemJunk.phase == .results:
            Text(Fmt.bytes(state.systemJunk.totalSize)).font(.caption2).foregroundStyle(.secondary)
        case .trashBins where state.trash.phase == .results:
            Text(Fmt.bytes(state.trash.totalSize)).font(.caption2).foregroundStyle(.secondary)
        case .updater where !state.updater.updates.isEmpty:
            Text("\(state.updater.updates.count)").font(.caption2.bold()).padding(.horizontal, 5).foregroundStyle(Theme.onAccent).background(Theme.accent, in: Capsule())
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func detail(for m: Module) -> some View {
        switch m {
        case .smartScan: SmartScanView()
        case .dashboard: DashboardView()
        case .systemJunk:
            CleanupModuleView(
                model: state.systemJunk, module: m,
                headline: "Liberte espaço ocupado por lixo",
                message: "Remova caches, registos, ficheiros temporários e restos de programação que se acumulam com o uso diário.",
                features: [("shippingbox", "Caches de apps e do sistema"), ("doc.text", "Registos e relatórios de falhas"),
                           ("hammer", "Lixo do Xcode e de gestores de pacotes"), ("wrench.and.screwdriver", "Preferências e itens de arranque danificados")]
            )
        case .mailAttachments:
            CleanupModuleView(
                model: state.mail, module: m,
                headline: "Recupere espaço do Mail",
                message: "Remova cópias locais de anexos e ficheiros abertos a partir do Mail. As mensagens no servidor não são afetadas.",
                features: [("paperclip", "Anexos que abriu no Mail"), ("envelope", "Cópias locais nas caixas de correio")]
            )
        case .trashBins:
            CleanupModuleView(
                model: state.trash, module: m,
                headline: "Esvazie todos os Lixos",
                message: "Esvazie o Lixo do disco de arranque e dos discos externos ligados, de uma só vez.",
                features: [("trash", "Lixo do utilizador"), ("externaldrive", "Lixo de discos externos")],
                cleanTitle: "Esvaziar"
            )
        case .privacy:
            CleanupModuleView(
                model: state.privacy, module: m,
                headline: "Apague o seu rasto digital",
                message: "Limpe o histórico de navegação, cookies, caches e listas de itens recentes. Palavras-passe e marcadores nunca são tocados.",
                features: [("safari", "Safari, Chrome, Firefox, Edge, Brave, Opera, Arc…"), ("clock", "Documentos e apps recentes"),
                           ("eye", "Miniaturas do Quick Look")]
            )
        case .optimization: OptimizationView()
        case .maintenance: MaintenanceView()
        case .uninstaller: UninstallerView()
        case .updater: UpdaterView()
        case .extensions: ExtensionsView()
        case .spaceLens: SpaceLensView()
        case .largeFiles: LargeFilesView()
        case .duplicates: DuplicatesView()
        case .shredder: ShredderView()
        }
    }
}
