import SwiftUI

struct ContentView: View {
    @ObservedObject private var state = AppState.shared
    // The sidebar badges follow these models.
    @ObservedObject private var systemJunk = AppState.shared.systemJunk
    @ObservedObject private var trash = AppState.shared.trash
    @ObservedObject private var updater = AppState.shared.updater
    @ViewState private var access: Permissions.AccessState = Permissions.hasFullDiskAccess ? .granted : .denied
    @ViewState private var showFDA = false
    @ViewState private var showConsent = false

    var body: some View {
        split
        .sheet(isPresented: $showFDA, onDismiss: { Task { access = await Permissions.accessState() } }) {
            FullDiskAccessView(initialState: access)
        }
        // On first launch, asks about statistics; the disk access assistant comes next
        // (only one sheet can be shown at a time).
        .sheet(isPresented: $showConsent, onDismiss: { Task { await checkAccessAtLaunch() } }) {
            AnalyticsConsentView()
        }
        .task {
            if Analytics.isAvailable && !AppSettings.shared.analyticsAsked {
                showConsent = true
            } else {
                await checkAccessAtLaunch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { access = await Permissions.accessState() }
        }
    }

    /// macOS 13 or later: NavigationSplitView. macOS 12: NavigationView with a sidebar.
    @ViewBuilder
    private var split: some View {
        if #available(macOS 13, *) {
            NavigationSplitView {
                sidebar.navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 260)
            } detail: {
                detailPane
            }
        } else {
            NavigationView {
                sidebar.frame(minWidth: 210, idealWidth: 230, maxWidth: 260)
                detailPane
            }
        }
    }

    /// List(selection:) with a non-optional value only exists from macOS 13.
    private var selection: Binding<Module?> {
        Binding(get: { state.selection }, set: { if let m = $0 { state.selection = m } })
    }

    private var sidebar: some View {
        List(selection: selection) {
            ForEach(ModuleSection.allCases, id: \.self) { section in
                let modules = Module.allCases.filter { $0.section == section }
                if section == .none {
                    ForEach(modules) { row($0) }
                } else {
                    Section(section.title) {
                        ForEach(modules) { row($0) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if access != .granted {
                Button {
                    showFDA = true
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: access == .needsRelaunch ? "arrow.clockwise.circle" : "lock.open.trianglebadge.exclamationmark")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(access == .needsRelaunch ? "Reopen Prune" : "Full Disk Access").font(.caption.bold())
                            Text(access == .needsRelaunch
                                 ? "Permission granted. Reopen Prune to apply it."
                                 : "Needed to scan Safari, Mail and protected folders.").font(.caption2)
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
    }

    private var detailPane: some View {
        // Pins the content to the column's real size (the background must not dictate the height).
        GeometryReader { geo in
            detail(for: state.selection)
                .id(state.selection)
                .transition(.opacity)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(ModuleBackground(module: state.selection))
        .animation(.easeInOut(duration: 0.25), value: state.selection)
        .onChange(of: state.selection) { m in Analytics.track("module_view", ["module": m.rawValue]) }
    }

    /// Right after an update, macOS may not recognize the new app for a moment.
    /// So it checks again for a few seconds before showing the assistant,
    /// and tells "no permission" apart from "permission granted but the app must be reopened".
    private func checkAccessAtLaunch() async {
        var inProcess = Permissions.hasFullDiskAccess
        for _ in 0..<6 where !inProcess {
            try? await Task.sleep(nanoseconds: 500_000_000)
            inProcess = Permissions.hasFullDiskAccess
        }
        access = inProcess ? .granted : (await Permissions.hasFullDiskAccessFresh() ? .needsRelaunch : .denied)
        Permissions.log("launch: access=\(access) version=\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")")
        switch access {
        case .granted: break
        case .needsRelaunch: showFDA = true
        case .denied: showFDA = !AppSettings.shared.fdaOnboardingDismissed
        }
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
        case .systemJunk where systemJunk.phase == .results:
            Text(Fmt.bytes(systemJunk.totalSize)).font(.caption2).foregroundStyle(.secondary)
        case .trashBins where trash.phase == .results:
            Text(Fmt.bytes(trash.totalSize)).font(.caption2).foregroundStyle(.secondary)
        case .updater where !updater.updates.isEmpty:
            Text("\(updater.updates.count)").font(.caption2.bold()).padding(.horizontal, 5).foregroundStyle(Theme.onAccent).background(Theme.accent, in: Capsule())
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
                headline: String(localized: "Free up disk space"),
                message: String(localized: "Caches, logs and temporary files pile up with use. Prune finds them and removes them safely."),
                features: [("shippingbox", String(localized: "App and system caches")), ("doc.text", String(localized: "Logs and crash reports")),
                           ("hammer", String(localized: "Xcode and package managers")), ("wrench.and.screwdriver", String(localized: "Broken preferences and login items"))]
            )
        case .mailAttachments:
            CleanupModuleView(
                model: state.mail, module: m,
                headline: String(localized: "Reclaim space from Mail"),
                message: String(localized: "Remove local copies of attachments. Messages on the server stay intact."),
                features: [("paperclip", String(localized: "Opened attachments")), ("envelope", String(localized: "Local copies in mailboxes"))]
            )
        case .trashBins:
            CleanupModuleView(
                model: state.trash, module: m,
                headline: String(localized: "Empty all Trash bins"),
                message: String(localized: "The Trash of your Mac and of external drives, in one go."),
                features: [("trash", String(localized: "User Trash")), ("externaldrive", String(localized: "External drive Trash"))],
                cleanTitle: String(localized: "Empty")
            )
        case .privacy:
            CleanupModuleView(
                model: state.privacy, module: m,
                headline: String(localized: "Erase your digital footprint"),
                message: String(localized: "History, cookies, caches and recent items. Passwords and bookmarks stay intact."),
                features: [("safari", String(localized: "Safari, Chrome, Firefox, Edge, Brave, Opera, Arc…")), ("clock", String(localized: "Recent documents and apps")),
                           ("eye", String(localized: "Quick Look thumbnails"))]
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
