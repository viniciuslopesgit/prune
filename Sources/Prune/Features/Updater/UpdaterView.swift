import SwiftUI

struct UpdaterView: View {
    private var state: AppState { .shared }
    @ObservedObject private var model = AppState.shared.updater

    var body: some View {
        VStack(spacing: 0) {
            if model.checking {
                ScanningView(module: .updater, title: String(localized: "Looking for updates…"), detail: model.progressText)
            } else if !model.checked {
                ModuleHeader(module: .updater)
                HeroView(
                    module: .updater, headline: String(localized: "Keep your apps up to date"),
                    message: String(localized: "Apps downloaded from the Internet and Homebrew packages, in one place."),
                    features: [("globe", String(localized: "Apps downloaded from the Internet")), ("mug", model.hasBrew ? String(localized: "Homebrew apps and tools") : String(localized: "Homebrew (not installed)")),
                               ("bag", String(localized: "Shortcut to the App Store"))],
                    buttonTitle: String(localized: "Check")
                ) { Task { await model.check() } }
            } else {
                ModuleHeader(module: .updater, subtitle: model.updates.isEmpty ? String(localized: "Everything up to date") : Fmt.count(model.updates.count, String(localized: "update available"), String(localized: "updates available"))) {
                    Button("App Store") { model.openAppStoreUpdates() }.buttonStyle(.bordered)
                    Button { Task { await model.check() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.bordered)
                }
                GlassPanel {
                    if model.updates.isEmpty {
                        EmptyStateView(icon: "checkmark.seal", title: String(localized: "All apps are up to date"),
                                       message: String(localized: "App Store apps are updated in the App Store."))
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
                                    Pill(text: u.source.title)
                                    if let notes = u.notesURL {
                                        Link("What's new", destination: notes).font(.caption)
                                    }
                                }
                                .padding(.vertical, 3)
                                .listRowBackground(Color.clear)
                            }
                        }
                        .hiddenScrollBackground()
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
                ActionFooter(summary: Fmt.count(model.updates.filter(\.selected).count, String(localized: "update selected"), String(localized: "updates selected")),
                             buttonTitle: model.installing ? String(localized: "Updating…") : String(localized: "Update"),
                             disabled: model.installing || !model.updates.contains(where: \.selected)) {
                    Task { await model.updateSelected() }
                }
            }
        }
    }
}
