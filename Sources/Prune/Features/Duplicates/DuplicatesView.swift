import SwiftUI
import UniformTypeIdentifiers

struct DuplicatesView: View {
    private var state: AppState { .shared }
    @ObservedObject private var model = AppState.shared.duplicates
    @ViewState private var confirm = false

    var body: some View {
        VStack(spacing: 0) {
            if model.scanning {
                ScanningView(module: .duplicates, title: model.mode == .exact ? String(localized: "Looking for duplicates…") : String(localized: "Comparing photos…"), detail: model.progressText)
            } else if !model.scanned {
                ModuleHeader(module: .duplicates)
                setup(model)
            } else {
                ModuleHeader(module: .duplicates, subtitle: model.groups.isEmpty ? String(localized: "No duplicates") : String(localized: "\(Fmt.count(model.groups.count, String(localized: "group"), String(localized: "groups"))) · \(Fmt.bytes(model.wasted)) in copies")) {
                    Button("New scan") { model.scanned = false }.buttonStyle(.bordered)
                }
                if let msg = model.message {
                    StatusBanner(text: msg, icon: "checkmark.circle", actionTitle: "OK") { model.message = nil }
                        .padding(.horizontal, 32).padding(.bottom, 8)
                }
                if model.groups.isEmpty {
                    EmptyStateView(icon: "checkmark.circle", title: String(localized: "No duplicates"), message: String(localized: "No copies in the chosen folders."))
                } else {
                    HStack(spacing: 14) {
                        GlassPanel { groupList(model) }.frame(width: 340)
                        GlassPanel { groupDetail(model) }
                    }
                    .padding(.horizontal, 32).padding(.bottom, 14)
                    ActionFooter(summary: String(localized: "\(Fmt.bytes(model.markedSize)) selected"), buttonTitle: String(localized: "Remove"),
                                 disabled: model.marked.isEmpty,
                                 secondary: model.mode == .exact ? (String(localized: "Auto select"), { model.autoSelect() }) : nil) { confirm = true }
                        .confirm(String(localized: "Remove \(Fmt.count(model.marked.count, String(localized: "copy"), String(localized: "copies")))?"), isPresented: $confirm,
                                 message: String(localized: "At least one copy of each file is always kept."), button: String(localized: "Remove")) {
                            Task { await model.removeMarked() }
                        }
                }
            }
        }
    }

    private func setup(_ model: DuplicatesModel) -> some View {
        return VStack(spacing: 20) {
            ModuleArtwork(module: .duplicates).frame(width: 200, height: 200)
            Picker("", selection: $model.mode) {
                ForEach(DuplicatesModel.Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 380)
            Text(model.mode == .exact
                 ? "Files with identical contents, even with different names."
                 : "Look-alike photos: bursts, edits and repeated screenshots.")
                .foregroundStyle(.secondary)
            GlassPanel {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.roots, id: \.self) { url in
                        HStack {
                            FileIcon(url: url, size: 20)
                            Text(url.displayPath)
                            Spacer()
                            Button { model.roots.removeAll { $0 == url } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                    }
                    Button { addFolder(model) } label: { Label("Add folder", systemImage: "plus") }.buttonStyle(.borderless)
                }
                .padding(14)
            }
            .frame(width: 460)
            if model.mode == .exact {
                Stepper("Ignore files smaller than \(model.minKB) KB", value: $model.minKB, in: 0...10_000, step: 50).frame(width: 380)
            } else {
                HStack {
                    Text("Similarity")
                    Slider(value: $model.similarity, in: 0.2...0.8) { Text("") } minimumValueLabel: { Text("Strict") } maximumValueLabel: { Text("Loose") }
                }
                .frame(width: 420)
            }
            BigActionButton(title: String(localized: "Scan"), disabled: model.roots.isEmpty) { Task { await model.scan() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func addFolder(_ model: DuplicatesModel) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { model.roots += panel.urls.filter { !model.roots.contains($0) } }
    }

    private func groupList(_ model: DuplicatesModel) -> some View {
        List(model.groups) { g in
            HStack(spacing: 10) {
                if let first = g.files.first {
                    if g.similar {
                        ThumbnailView(url: first.url, maxPixel: 96, iconSize: 32, fill: true)
                            .frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        FileIcon(url: first.url, size: 32)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(first.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Text(Fmt.count(g.files.count, String(localized: "copy"), String(localized: "copies"))).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                SizeLabel(bytes: g.similar ? g.files.reduce(0) { $0 + $1.size } : g.wasted).font(.caption)
            }
            .padding(.vertical, 3).padding(.horizontal, 6)
            .background(model.focusedGroup == g.id ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture { model.focusedGroup = g.id }
            .listRowBackground(Color.clear).hiddenRowSeparator()
        }
        .hiddenScrollBackground()
    }

    @ViewBuilder
    private func groupDetail(_ model: DuplicatesModel) -> some View {
        if let g = model.groups.first(where: { $0.id == model.focusedGroup }) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                    ForEach(g.files) { f in
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack(alignment: .topLeading) {
                                Group {
                                    if UTType(filenameExtension: f.url.pathExtension)?.conforms(to: .image) == true {
                                        ThumbnailView(url: f.url, maxPixel: 400, iconSize: 96)
                                    } else {
                                        FileIcon(url: f.url, size: 96)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 130, maxHeight: 130)
                                CheckBox(state: model.marked.contains(f.id)) { model.toggle(f) }.padding(6)
                            }
                            Text(f.url.lastPathComponent).font(.callout).lineLimit(1).truncationMode(.middle)
                            Text(f.url.deletingLastPathComponent().displayPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            HStack {
                                Text(Fmt.date(f.created)).font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                SizeLabel(bytes: f.size).font(.caption)
                                RevealButton(url: f.url)
                            }
                        }
                        .padding(10)
                        .background(model.marked.contains(f.id) ? Theme.selection : Theme.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .padding(14)
            }
        } else {
            EmptyStateView(icon: "square.on.square", title: String(localized: "Choose a group"))
        }
    }
}
