import SwiftUI

struct ExtensionsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var model = state.extensions
        VStack(spacing: 0) {
            ModuleHeader(module: .extensions, subtitle: String(localized: "Extensions, plug-ins and widgets")) {
                Toggle("Show system", isOn: $model.showSystem).toggleStyle(.switch)
                Button { Task { await model.load() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.bordered)
            }
            if let msg = model.message {
                StatusBanner(text: msg, icon: "exclamationmark.triangle", actionTitle: "OK") { model.message = nil }
                    .padding(.horizontal, 32).padding(.bottom, 8)
            }
            HStack(spacing: 14) {
                GlassPanel {
                    List(ExtensionCategory.allCases) { cat in
                        HStack {
                            Image(systemName: cat.icon).frame(width: 22)
                            Text(cat.title)
                            Spacer()
                            Text("\(model.count(cat))").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.vertical, 4).padding(.horizontal, 6)
                        .background(model.category == cat ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onTapGesture { model.category = cat }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .scrollContentBackground(.hidden)
                }
                .frame(width: 260)
                GlassPanel {
                    if model.loading && !model.loaded {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        content(model)
                    }
                }
            }
            .padding(.horizontal, 32).padding(.bottom, 20)
        }
        .task { if !model.loaded { await model.load() } }
    }

    @ViewBuilder
    private func content(_ model: ExtensionsModel) -> some View {
        let cat = model.category
        if cat == .browsers {
            if model.browser.isEmpty {
                EmptyStateView(icon: "globe", title: String(localized: "No extensions in other browsers"))
            } else {
                List(model.browser) { ext in
                    HStack(spacing: 10) {
                        Image(systemName: "puzzlepiece.extension").frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(ext.name).lineLimit(1)
                                if !ext.fromStore { Pill(text: String(localized: "Not from store"), color: Theme.amber) }
                            }
                            Text("\(ext.browser) · v\(ext.version)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        RevealButton(url: ext.url)
                        Button("Remove") { Task { await model.remove(ext) } }.buttonStyle(.bordered)
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
            }
        } else {
            let exts = model.extensions(in: cat)
            let files = model.files[cat] ?? []
            if exts.isEmpty && files.isEmpty {
                EmptyStateView(icon: cat.icon, title: String(localized: "Nothing installed in this category"),
                               message: model.showSystem ? nil : String(localized: "Turn on \"Show system\" to include Apple's."))
            } else {
                List {
                    if !exts.isEmpty {
                        Section("App extensions") {
                            ForEach(exts) { ext in
                                HStack(spacing: 10) {
                                    if let range = ext.path.range(of: ".app/") {
                                        FileIcon(url: URL(fileURLWithPath: String(ext.path[..<range.lowerBound]) + ".app"), size: 26)
                                    } else {
                                        Image(systemName: cat.icon).frame(width: 26)
                                    }
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(ext.name).lineLimit(1)
                                        Text(ext.parent.map { "\($0) · \(ext.identifier)" } ?? ext.identifier)
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    Toggle("", isOn: Binding(get: { ext.enabled }, set: { _ in Task { await model.toggle(ext) } }))
                                        .toggleStyle(.switch).labelsHidden()
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                    if !files.isEmpty {
                        Section("Plug-ins") {
                            ForEach(files) { f in
                                HStack(spacing: 10) {
                                    FileIcon(url: f.url, size: 26)
                                    VStack(alignment: .leading) {
                                        Text(f.url.deletingPathExtension().lastPathComponent)
                                        Text("\(f.kind) · \(f.url.deletingLastPathComponent().displayPath)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    SizeLabel(bytes: f.size)
                                    RevealButton(url: f.url)
                                    Button("Remove") { Task { await model.remove(f, category: cat) } }.buttonStyle(.bordered)
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }
}
