import SwiftUI

/// Consent prompt for statistics, shown once on first launch.
/// Declining is as easy as accepting; the choice can be changed in Settings ▸ General ▸ Statistics.
struct AnalyticsConsentView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                LeafMark(size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Help improve Prune?").font(Theme.display(20))
                    Text("Share anonymous usage statistics. They show us what to improve.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                item("checkmark", Theme.leaf, String(localized: "Sections you use, scans and cleanups"))
                item("checkmark", Theme.leaf, String(localized: "Totals of space found and freed"))
                item("checkmark", Theme.leaf, String(localized: "Prune and macOS version"))
                item("xmark", Theme.amber, String(localized: "Never names of files, folders, apps or contents"))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Sent to Google Analytics. Change it at any time in Settings ▸ General.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Don't share") { answer(false) }
                    .controlSize(.large)
                Button("Share") { answer(true) }
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
        // This session's launch only counts from the moment of consent.
        Analytics.track("app_open")
        dismiss()
    }
}
