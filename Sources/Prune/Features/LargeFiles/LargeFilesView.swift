import SwiftUI

struct LargeFilesView: View {
    private var state: AppState { .shared }
    @ObservedObject private var model = AppState.shared.largeFiles
    @ViewState private var confirm: Bool = false
    @ViewState private var shredMode = false

    var body: some View {
        VStack(spacing: 0) {
            if model.scanning {
                ScanningView(module: .largeFiles, title: String(localized: "Looking for large files…"), detail: model.progressText)
            } else if !model.scanned {
                ModuleHeader(module: .largeFiles)
                HeroView(
                    module: .largeFiles, headline: String(localized: "Find large, forgotten files"),
                    message: String(localized: "Videos, disk images and archives you have not opened in a long time."),
                    features: [("arrow.up.right.and.arrow.down.left", String(localized: "By size")), ("calendar", String(localized: "By last opened")),
                               ("square.grid.2x2", String(localized: "By file type"))],
                    footnote: model.includeLibrary ? String(localized: "Scans your home folder, including the Library.") : String(localized: "Scans your home folder.")
                ) { Task { await model.scan() } }
                Toggle("Include the Library folder", isOn: $model.includeLibrary).padding(.bottom, 150)
            } else {
                ModuleHeader(module: .largeFiles, subtitle: "\(Fmt.files(model.filtered.count)) · \(Fmt.bytes(model.filtered.reduce(0) { $0 + $1.size }))") {
                    Button { Task { await model.scan() } } label: { Label("Scan again", systemImage: "arrow.clockwise") }.buttonStyle(.bordered)
                }
                filters(model)
                if let msg = model.message {
                    StatusBanner(text: msg, icon: "checkmark.circle", actionTitle: "OK") { model.message = nil }
                        .padding(.horizontal, 32).padding(.bottom, 8)
                }
                HStack(spacing: 14) {
                    GlassPanel {
                        List(FileKind.allCases) { k in
                            HStack {
                                Image(systemName: k.icon).frame(width: 22)
                                Text(k.title)
                                Spacer()
                                Text("\(model.count(k))").foregroundStyle(.secondary).monospacedDigit()
                            }
                            .padding(.vertical, 4).padding(.horizontal, 6)
                            .background(model.kind == k ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                            .onTapGesture { model.kind = k }
                            .listRowBackground(Color.clear).hiddenRowSeparator()
                        }
                        .hiddenScrollBackground()
                    }
                    .frame(width: 220)
                    GlassPanel {
                        List(model.filtered) { f in
                            HStack(spacing: 10) {
                                CheckBox(state: model.selected.contains(f.id)) {
                                    if model.selected.contains(f.id) { model.selected.remove(f.id) } else { model.selected.insert(f.id) }
                                }
                                FileIcon(url: f.url, size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(f.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                    Text(f.url.deletingLastPathComponent().displayPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                }
                                Spacer()
                                Text("Opened \(Fmt.relative(f.accessed ?? f.modified))").font(.caption).foregroundStyle(.secondary).frame(width: 150, alignment: .trailing)
                                SizeLabel(bytes: f.size).frame(width: 80, alignment: .trailing)
                                RevealButton(url: f.url)
                            }
                            .listRowBackground(Color.clear)
                        }
                        .hiddenScrollBackground()
                        .overlay { if model.filtered.isEmpty { EmptyStateView(icon: "doc", title: String(localized: "No files match these filters")) } }
                    }
                }
                .padding(.horizontal, 32).padding(.bottom, 14)
                ActionFooter(summary: "\(Fmt.count(model.selected.count, String(localized: "file selected"), String(localized: "files selected"))) · \(Fmt.bytes(model.selectedSize))",
                             buttonTitle: String(localized: "Remove"), disabled: model.selected.isEmpty || model.working,
                             secondary: (String(localized: "Shred"), { shredMode = true; confirm = true })) {
                    shredMode = false
                    confirm = true
                }
                .confirm(shredMode ? String(localized: "Shred securely?") : String(localized: "Remove files?"), isPresented: $confirm,
                         message: shredMode ? String(localized: "The files are overwritten and deleted. They cannot be recovered.")
                                            : (AppSettings.shared.filesDeleteMode == .trash ? String(localized: "The files go to the Trash.") : String(localized: "The files are deleted permanently.")),
                         button: shredMode ? String(localized: "Shred") : String(localized: "Remove")) {
                    Task { await model.removeSelected(shred: shredMode) }
                }
            }
        }
    }

    private func filters(_ model: LargeFilesModel) -> some View {
        return HStack(spacing: 16) {
            Picker("Minimum size", selection: $model.minMB) {
                ForEach([10, 50, 100, 500, 1000, 5000], id: \.self) { Text($0 >= 1000 ? "\($0 / 1000) GB" : "\($0) MB").tag($0) }
            }
            .frame(width: 220)
            Picker("Last opened", selection: $model.age) {
                ForEach(FileAge.allCases) { Text($0.title).tag($0) }
            }
            .frame(width: 240)
            Spacer()
        }
        .padding(.horizontal, 32).padding(.bottom, 10)
    }
}
