import AppKit
import SwiftUI

// MARK: - Tema

/// Identidade do Prune: uma folha escura sobre marfim, como o ícone. Monocromática (tinta e marfim),
/// com um só acento natural, o verde-salva da folha, para estados e controlos do sistema.
/// Cores adaptativas (modo claro e escuro) e uma só família tipográfica, com a largura como variável.
enum Theme {
    static let background = adaptive(light: 0xF5F4EE, dark: 0x1C1C19)
    static let panel = adaptive(light: 0xFBFAF6, dark: 0x252521)
    static let stone = adaptive(light: 0xE8E6DC, dark: 0x2D2D28)
    /// Tinta no modo claro, marfim no escuro: ações principais, anéis, seleção.
    static let accent = adaptive(light: 0x1F1F1C, dark: 0xF5F4EE)
    /// Texto sobre `accent`.
    static let onAccent = adaptive(light: 0xF5F4EE, dark: 0x1F1F1C)
    static let leaf = adaptive(light: 0x5E7A4F, dark: 0x9DBB88)
    static let amber = adaptive(light: 0xA86A14, dark: 0xD9A04A)
    static let hairline = Color.primary.opacity(0.08)
    static let inset = Color.primary.opacity(0.045)
    static let selection = Color.primary.opacity(0.09)

    /// Títulos e números: SF Pro Expanded.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.expanded)
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(Color(hex: isDark ? dark : light))
        })
    }
}

// MARK: - Fundo e cabeçalhos

struct ModuleBackground: View {
    let module: Module
    var body: some View {
        Theme.background.ignoresSafeArea()
    }
}

struct ModuleHeader<Trailing: View>: View {
    let module: Module
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(module: Module, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.module = module
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(module.title).font(Theme.display(22))
                if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 32)
        .padding(.top, 26)
        .padding(.bottom, 14)
    }
}

/// Ecrã inicial de um módulo: texto e ação à esquerda, a vidraça à direita.
struct HeroView: View {
    let module: Module
    let headline: String
    let message: String
    var features: [(String, String)] = []
    var buttonTitle = "Analisar"
    var footnote: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 56) {
            VStack(alignment: .leading, spacing: 0) {
                Text(headline)
                    .font(Theme.display(32))
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                if !features.isEmpty {
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(features, id: \.1) { f in
                            HStack(spacing: 12) {
                                Image(systemName: f.0).foregroundStyle(Theme.accent).frame(width: 24)
                                Text(f.1)
                            }
                        }
                    }
                    .padding(.top, 26)
                }
                HStack(spacing: 16) {
                    BigActionButton(title: buttonTitle, action: action)
                    if let footnote {
                        Text(footnote).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 32)
            }
            .frame(maxWidth: 440, alignment: .leading)
            ModuleArtwork(module: module).frame(width: 300, height: 300)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A ilustração dos módulos: a folha do ícone, com o símbolo do módulo recortado no meio.
/// Com `swaying`, a folha baloiça devagar (é o único movimento contínuo da app, durante as análises).
struct ModuleArtwork: View {
    let module: Module
    var swaying = false
    @State private var tilt: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let shape = RoundedRectangle(cornerRadius: side * 0.09, style: .continuous)
            ZStack {
                shape.fill(Theme.stone)
                ZStack {
                    LeafShape().fill(Theme.accent)
                    LeafShape().stroke(Theme.accent, style: StrokeStyle(lineWidth: side * 0.022, lineCap: .round))
                }
                .rotationEffect(.degrees(tilt), anchor: UnitPoint(x: 0.27, y: 0.73))
                Image(systemName: module.icon)
                    .font(.system(size: side * 0.15, weight: .medium))
                    .foregroundStyle(Theme.stone)
                    .offset(x: side * 0.025, y: -side * 0.025)
                    .rotationEffect(.degrees(tilt), anchor: UnitPoint(x: 0.27, y: 0.73))
            }
            .clipShape(shape)
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
        .onAppear {
            guard swaying, !reduceMotion else { return }
            tilt = -4
            // Fora da transação de layout inicial, para não animar a posição da vista.
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { tilt = 4 }
            }
        }
    }
}

/// A folha do ícone (scripts/make_icon.swift), num quadrado unitário: ponta em cima à direita, pé em baixo à esquerda.
struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        // Mesma geometria do ícone, numa grelha de 1024 com a folha a ocupar a área útil de 824.
        let k = s / 824
        let L = 235 * k, W = 132 * k
        var leaf = Path()
        leaf.move(to: CGPoint(x: -L, y: 0))
        leaf.addCurve(to: CGPoint(x: L, y: 0), control1: CGPoint(x: -L * 0.55, y: W * 1.25), control2: CGPoint(x: L * 0.45, y: W * 0.95))
        leaf.addCurve(to: CGPoint(x: -L, y: 0), control1: CGPoint(x: L * 0.45, y: -W * 0.95), control2: CGPoint(x: -L * 0.55, y: -W * 1.25))
        leaf.closeSubpath()
        // Pé, como um segmento fino (o traço é desenhado por quem usa a forma).
        leaf.move(to: CGPoint(x: -L + 20 * k, y: 0))
        leaf.addLine(to: CGPoint(x: -L - 85 * k, y: 0))
        let t = CGAffineTransform(translationX: rect.midX, y: rect.midY).rotated(by: -.pi / 4)
        return leaf.applying(t)
    }
}

/// Botão principal: cápsula cor de tinta (marfim no modo escuro).
struct BigActionButton: View {
    let title: String
    var disabled = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.display(15))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 30)
                .frame(minWidth: 150, minHeight: 44)
                .background(Capsule().fill(Theme.accent.opacity(hover ? 0.85 : 1)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}

struct ScanningView: View {
    let module: Module
    let title: String
    let detail: String
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ModuleArtwork(module: module, swaying: true).frame(width: 240, height: 240)
            Text(title).font(Theme.display(24)).padding(.top, 34)
            Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 560)
                .padding(.top, 8)
            if let onCancel {
                Button("Parar", action: onCancel).buttonStyle(.bordered).padding(.top, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DoneView: View {
    let module: Module
    let title: String
    let message: String
    var failedCount = 0
    var onRetryAdmin: (() -> Void)?
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.leaf)
            Text(title).font(Theme.display(30)).padding(.top, 22)
            Text(message).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 10)
            if failedCount > 0 {
                VStack(spacing: 8) {
                    Text("\(failedCount) item(ns) não puderam ser removidos (em uso ou protegidos).")
                        .font(.callout).foregroundStyle(.secondary)
                    if let onRetryAdmin {
                        Button("Tentar com privilégios de administrador", action: onRetryAdmin).buttonStyle(.bordered)
                    }
                }
                .padding(.top, 16)
            }
            Button("Voltar", action: onBack).buttonStyle(.bordered).controlSize(.large).padding(.top, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Linhas e controlos

struct CheckBox: View {
    let state: Bool?  // nil = misto
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
            .help("Mostrar no Finder")
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

/// Barra inferior com total selecionado e botão principal.
struct ActionFooter: View {
    let summary: String
    let buttonTitle: String
    var disabled = false
    var secondary: (title: String, action: () -> Void)?
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(summary).font(Theme.display(14)).monospacedDigit()
            Spacer()
            if let secondary {
                Button(secondary.title, action: secondary.action).buttonStyle(.bordered).controlSize(.large)
            }
            BigActionButton(title: buttonTitle, disabled: disabled, action: action)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
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

/// Anel de percentagem (usado no Painel e na barra de menus).
struct RingGauge: View {
    let value: Double
    var lineWidth: CGFloat = 10
    var color: Color = Theme.accent
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle().trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: value)
        }
    }
}

struct Sparkline: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let step = values.count > 1 ? w / CGFloat(values.count - 1) : w
            Path { p in
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: CGFloat(i) * step, y: h - CGFloat(min(1, v)) * h)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            .stroke(Theme.accent, lineWidth: 1.5)
            Path { p in
                p.move(to: CGPoint(x: 0, y: h))
                for (i, v) in values.enumerated() {
                    p.addLine(to: CGPoint(x: CGFloat(i) * step, y: h - CGFloat(min(1, v)) * h))
                }
                p.addLine(to: CGPoint(x: w, y: h))
            }
            .fill(LinearGradient(colors: [Theme.accent.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom))
        }
    }
}

extension View {
    func confirm(_ title: String, isPresented: Binding<Bool>, message: String, button: String, action: @escaping () -> Void) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button(button, role: .destructive, action: action)
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}
