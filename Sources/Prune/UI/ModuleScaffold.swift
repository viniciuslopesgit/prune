import SwiftUI

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

/// A module's start screen: text and action on the left, the artwork on the right.
struct HeroView: View {
    let module: Module
    let headline: String
    let message: String
    var features: [(String, String)] = []
    var buttonTitle = String(localized: "Scan")
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

/// The modules' illustration: the icon's leaf, with the module's symbol cut out in the middle.
/// With `swaying`, the leaf sways slowly (the app's only continuous motion, during scans).
/// `symbol` replaces the module's symbol (e.g. a checkmark on the completion screen).
struct ModuleArtwork: View {
    let module: Module
    var symbol: String?
    var swaying = false
    @ViewState private var tilt: Double = 0
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
                Image(systemName: symbol ?? module.icon)
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
            // Outside the initial layout transaction, so the view's position is not animated.
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { tilt = 4 }
            }
        }
    }
}

/// The brand's leaf on its own, without a background: the only leaf used in the app (consent, menu bar…).
struct LeafMark: View {
    var size: CGFloat
    var color: Color = Theme.accent
    var body: some View {
        ZStack {
            LeafShape().fill(color)
            LeafShape().stroke(color, style: StrokeStyle(lineWidth: size * 0.022, lineCap: .round))
        }
        // The shape fills ~75% of the square (as in the icon); scales up to fill the requested size.
        .scaleEffect(1.3)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The icon's leaf (scripts/make_icon.swift), in a unit square: tip at the top right, stem at the bottom left.
struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        // Same geometry as the icon, on a 1024 grid with the leaf filling the 824 usable area.
        let k = s / 824
        let L = 235 * k, W = 132 * k
        var leaf = Path()
        leaf.move(to: CGPoint(x: -L, y: 0))
        leaf.addCurve(to: CGPoint(x: L, y: 0), control1: CGPoint(x: -L * 0.55, y: W * 1.25), control2: CGPoint(x: L * 0.45, y: W * 0.95))
        leaf.addCurve(to: CGPoint(x: -L, y: 0), control1: CGPoint(x: L * 0.45, y: -W * 0.95), control2: CGPoint(x: -L * 0.55, y: -W * 1.25))
        leaf.closeSubpath()
        // Stem, as a thin segment (the stroke is drawn by whoever uses the shape).
        leaf.move(to: CGPoint(x: -L + 20 * k, y: 0))
        leaf.addLine(to: CGPoint(x: -L - 85 * k, y: 0))
        let t = CGAffineTransform(translationX: rect.midX, y: rect.midY).rotated(by: -.pi / 4)
        return leaf.applying(t)
    }
}

/// Main button: ink-colored capsule (ivory in dark mode).
struct BigActionButton: View {
    let title: String
    var disabled = false
    let action: () -> Void
    @ViewState private var hover = false

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
                Button("Stop", action: onCancel).buttonStyle(.bordered).padding(.top, 20)
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
            ModuleArtwork(module: module, symbol: "checkmark").frame(width: 170, height: 170)
            Text(title).font(Theme.display(30)).padding(.top, 28)
            Text(message).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 10)
            if failedCount > 0 {
                VStack(spacing: 8) {
                    Text("\(failedSummary): in use or protected.")
                        .font(.callout).foregroundStyle(.secondary)
                    if let onRetryAdmin {
                        Button("Try with administrator privileges", action: onRetryAdmin).buttonStyle(.bordered)
                    }
                }
                .padding(.top, 16)
            }
            Button("Back", action: onBack).buttonStyle(.bordered).controlSize(.large).padding(.top, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failedSummary: String {
        Fmt.count(failedCount, String(localized: "item was not removed"), String(localized: "items were not removed"))
    }
}

/// Bottom bar with the selected total and the main button.
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
