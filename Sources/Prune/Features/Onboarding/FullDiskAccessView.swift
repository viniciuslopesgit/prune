import SwiftUI

/// Full Disk Access assistant. With this permission, macOS stops asking for authorization
/// folder by folder (Documents, Desktop, Downloads, other apps' data, Mail, Safari…).
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
                    step(1, String(localized: "Open System Settings.")) {
                        Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
                    }
                    step(2, String(localized: "Turn on Prune in the list. If it is not there, drag the app into it.")) {
                        Button("Show the app in Finder") { FS.reveal(Bundle.main.bundleURL) }
                    }
                    step(3, String(localized: "Come back to Prune. The permission is detected automatically.")) {
                        EmptyView()
                    }
                }
                .padding(14)
                .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Nothing is deleted without your confirmation.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                if state == .denied {
                    Button("Don't show again") {
                        AppSettings.shared.fdaOnboardingDismissed = true
                        dismiss()
                    }
                    .buttonStyle(.borderless)
                }
                Spacer()
                switch state {
                case .granted:
                    Button("Continue") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                case .needsRelaunch:
                    Button("Later") { dismiss() }
                    Button("Reopen Prune") { Permissions.relaunch() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                case .denied:
                    Button("Not now") { dismiss() }
                    Button(checking ? "Checking…" : "Check") { Task { await refresh() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(checking)
                }
            }
        }
        .padding(26)
        .frame(width: 560)
        // Detects the permission when the user comes back from System Settings, without touching the button
        // (it used to check every 1.5 s and the button flipped to "Checking…" on its own).
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard state != .granted else { return }
            Task { state = await Permissions.accessState() }
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
        case .granted: String(localized: "Full Disk Access granted")
        case .needsRelaunch: String(localized: "Prune needs to be reopened")
        case .denied: String(localized: "Give Prune full disk access")
        }
    }

    private var subtitle: String {
        switch state {
        case .granted: String(localized: "Prune no longer asks for authorization folder by folder.")
        case .needsRelaunch: String(localized: "The permission is granted. macOS applies it when you reopen the app.")
        case .denied: String(localized: "Without this permission, macOS asks for authorization for each protected folder.")
        }
    }

    /// Check requested by the user ("Check" button).
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
