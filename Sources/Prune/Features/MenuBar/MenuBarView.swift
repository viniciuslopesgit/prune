import SwiftUI

struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    private var stats: SystemStats { SystemStats.shared }
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
            Text("\(Int(stats.cpu * 100))%").monospacedDigit()
        }
        .onAppear { WindowOpener.shared.action = openWindow }
    }
}

struct MenuBarView: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    private var stats: SystemStats { SystemStats.shared }
    @State private var topApps: [ProcessInfoRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles").font(.title3)
                Text("Prune").font(.headline)
                Spacer()
                Text("Ligado há \(stats.uptimeText)").font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                tile("Disco", value: stats.diskUsedFraction, caption: "\(Fmt.bytes(stats.diskFree)) livres", icon: "internaldrive")
                tile("Memória", value: stats.memoryFraction, caption: Fmt.bytes(stats.memoryUsed), icon: "memorychip")
                tile("CPU", value: stats.cpu, caption: stats.thermalText, icon: "cpu")
            }

            VStack(alignment: .leading, spacing: 6) {
                Sparkline(values: stats.cpuHistory).frame(height: 36)
                HStack {
                    Label(SystemStats.speed(stats.netDown), systemImage: "arrow.down")
                    Spacer()
                    Label(SystemStats.speed(stats.netUp), systemImage: "arrow.up")
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Theme.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let b = stats.battery {
                HStack {
                    Image(systemName: b.charging ? "battery.100.bolt" : "battery.75")
                    Text("\(b.percent)%").monospacedDigit()
                    if let h = b.health { Text("· saúde \(Fmt.percent(h))").foregroundStyle(.secondary) }
                    if let c = b.cycleCount { Text("· \(c) ciclos").foregroundStyle(.secondary) }
                    Spacer()
                }
                .font(.callout)
            }

            if !topApps.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mais exigentes").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(topApps) { p in
                        HStack(spacing: 6) {
                            if let i = p.icon { Image(nsImage: i).resizable().frame(width: 16, height: 16) }
                            Text(p.name).lineLimit(1)
                            Spacer()
                            Text(String(format: "%.0f%%", p.cpu)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }

            Divider()
            HStack {
                Button("Análise Inteligente") {
                    state.selection = .smartScan
                    openMain()
                }
                Spacer()
                Button { openMain() } label: { Image(systemName: "macwindow") }.help("Abrir Prune")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.help("Sair")
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(width: 340)
        .task {
            while !Task.isCancelled {
                let all = await OptimizationService.processes()
                topApps = Array(all.filter(\.isApp).sorted { $0.cpu > $1.cpu }.prefix(4))
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func openMain() {
        WindowOpener.shared.action = openWindow
        WindowOpener.shared.openMain()
    }

    private func tile(_ title: String, value: Double, caption: String, icon: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RingGauge(value: value, lineWidth: 6, color: value > 0.85 ? Theme.amber : Theme.accent)
                Text(Fmt.percent(value)).font(.caption.bold()).monospacedDigit()
            }
            .frame(width: 54, height: 54)
            Label(title, systemImage: icon).font(.caption.bold())
            Text(caption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
