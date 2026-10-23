import SwiftUI

struct CheckBox: View {
    let state: Bool?  // nil = mixed
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: state == nil ? "minus.circle.fill" : (state! ? "checkmark.circle.fill" : "circle"))
                .font(.system(size: 17))
                .foregroundStyle(state == false ? Color.secondary : Theme.accent)
        }
        .buttonStyle(.plain)
    }
}

struct FileIcon: View {
    let url: URL
    var size: CGFloat = 28
    var body: some View {
        Image(nsImage: FS.icon(for: url)).resizable().frame(width: size, height: size)
    }
}

struct SizeLabel: View {
    let bytes: Int64
    var body: some View {
        Text(Fmt.bytes(bytes)).monospacedDigit().foregroundStyle(.secondary)
    }
}

struct RevealButton: View {
    let url: URL
    var body: some View {
        Button { FS.reveal(url) } label: { Image(systemName: "magnifyingglass") }
            .buttonStyle(.borderless)
            .help("Show in Finder")
    }
}

struct GlassPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline))
    }
}

struct StatusBanner: View {
    let text: String
    var icon = "info.circle"
    var actionTitle: String?
    var action: (() -> Void)?
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.amber)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.bordered).controlSize(.small)
            }
        }
        .padding(10)
        .background(Theme.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(title).font(Theme.display(18))
            if let message { Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct Pill: View {
    let text: String
    var color: Color = Theme.accent
    var body: some View {
        Text(text).font(.caption2.bold())
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
    }
}
