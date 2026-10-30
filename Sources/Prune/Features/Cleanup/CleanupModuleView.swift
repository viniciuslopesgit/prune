import SwiftUI

/// View shared by the category-based cleanup modules.
struct CleanupModuleView: View {
    @ObservedObject var model: CleanupModel
    let module: Module
    let headline: String
    let message: String
    var features: [(String, String)] = []
    var cleanTitle = String(localized: "Clean")

    @ViewState private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            switch model.phase {
            case .idle:
                ModuleHeader(module: module)
                HeroView(module: module, headline: headline, message: message, features: features) {
                    Task { await model.scan() }
                }
            case .scanning:
                ScanningView(module: module, title: String(localized: "Scanning…"), detail: model.progressText)
            case .cleaning:
                ScanningView(module: module, title: String(localized: "Cleaning…"), detail: model.progressText)
            case .results:
                ModuleHeader(module: module, subtitle: model.categories.isEmpty ? nil : String(localized: "\(Fmt.bytes(model.totalSize)) found")) {
                    Button { Task { await model.scan() } } label: { Label("Scan again", systemImage: "arrow.clockwise") }
                        .buttonStyle(.bordered)
                }
                if model.categories.isEmpty {
                    EmptyStateView(icon: "sparkles", title: String(localized: "All clean"), message: String(localized: "Nothing to remove."))
                    Button("Back") { model.reset() }.buttonStyle(.bordered).padding(.bottom, 30)
                } else {
                    results
                }
            case .done:
                DoneView(
                    module: module, title: String(localized: "Done"),
                    message: String(localized: "\(Fmt.bytes(model.report.freed)) freed · \(Fmt.items(model.report.removed))."),
                    failedCount: model.report.failed.count,
                    onRetryAdmin: { Task { await model.retryFailedAsAdmin() } },
                    onBack: { model.phase = model.categories.contains { !$0.items.isEmpty } ? .results : .idle }
                )
            }
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            let blockers = model.runningBlockers
            if !blockers.isEmpty {
                StatusBanner(
                    text: String(localized: "Close \(blockers.compactMap(\.localizedName).joined(separator: ", ")) to clean safely."),
                    icon: "exclamationmark.triangle", actionTitle: String(localized: "Close apps")
                ) { blockers.forEach { $0.terminate() } }
                .padding(.horizontal, 32).padding(.bottom, 10)
            }
            HStack(spacing: 14) {
                GlassPanel {
                    List {
                        ForEach(model.categories) { cat in
                            categoryRow(cat)
                        }
                    }
                    .hiddenScrollBackground()
                }
                .frame(width: 320)

                GlassPanel {
                    if let cat = model.selectedCategory {
                        itemsList(cat)
                    } else {
                        EmptyStateView(icon: "list.bullet", title: String(localized: "Choose a category"))
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 14)

            ActionFooter(
                summary: String(localized: "\(Fmt.bytes(model.selectedSize)) selected"),
                buttonTitle: cleanTitle,
                disabled: model.selectedCount == 0,
                secondary: (String(localized: "Select all"), { model.setAll(true) })
            ) { confirming = true }
        }
        .confirm("\(cleanTitle) \(Fmt.bytes(model.selectedSize))?", isPresented: $confirming,
                 message: Fmt.count(model.selectedCount, String(localized: "item will be removed"), String(localized: "items will be removed")) + ".", button: cleanTitle) {
            Task { await model.clean() }
        }
    }

    private func categoryRow(_ cat: CleanCategory) -> some View {
        HStack(spacing: 10) {
            CheckBox(state: cat.allSelected ? true : (cat.noneSelected ? false : nil)) { model.toggleCategory(cat.id) }
            Image(systemName: cat.icon).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(cat.name).lineLimit(1)
                Text(Fmt.items(cat.items.count)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            SizeLabel(bytes: cat.totalSize).font(.callout)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(model.selectedCategoryID == cat.id ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture { model.selectedCategoryID = cat.id }
        .listRowBackground(Color.clear)
        .hiddenRowSeparator()
    }

    private func itemsList(_ cat: CleanCategory) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(cat.name).font(.title3.bold())
                Text(cat.info).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let w = cat.warning {
                    Label(w, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.amber)
                }
            }
            .padding(16)
            Divider().opacity(0.3)
            List {
                ForEach(cat.items) { item in
                    HStack(spacing: 10) {
                        CheckBox(state: item.selected) { model.toggleItem(category: cat.id, item: item.id) }
                        FileIcon(url: item.url, size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).lineLimit(1).truncationMode(.middle)
                            Text(item.detail ?? item.url.deletingLastPathComponent().displayPath)
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        SizeLabel(bytes: item.size).font(.callout)
                        RevealButton(url: item.url)
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(Color.clear)
                    .contextMenu {
                        Button("Show in Finder") { FS.reveal(item.url) }
                        Button("Always ignore") {
                            AppSettings.shared.ignoredPaths.append(item.url.path)
                            if item.selected { model.toggleItem(category: cat.id, item: item.id) }
                        }
                    }
                }
            }
            .hiddenScrollBackground()
        }
    }
}
