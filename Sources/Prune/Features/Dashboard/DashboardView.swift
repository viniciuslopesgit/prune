import SwiftUI

struct DashboardView: View {
    private var state: AppState { .shared }
    @ObservedObject private var stats = SystemStats.shared
    @ViewState private var security: SecurityStatus?
    @ViewState private var checkingSecurity = false

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .dashboard, subtitle: String(localized: "\(Host.current().localizedName ?? "Mac"), up for \(stats.uptimeText)"))
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        gaugeCard(title: String(localized: "Disk"), value: stats.diskUsedFraction, icon: "internaldrive",
                                  lines: [String(localized: "\(Fmt.bytes(stats.diskFree)) free"), String(localized: "of \(Fmt.bytes(stats.diskTotal))")]) {
                            Button("Free up space") { state.selection = .systemJunk }.buttonStyle(.bordered)
                        }
                        gaugeCard(title: String(localized: "Memory"), value: stats.memoryFraction, icon: "memorychip",
                                  lines: [String(localized: "\(Fmt.bytes(stats.memoryUsed)) used"), String(localized: "of \(Fmt.bytes(stats.memoryTotal)) · swap \(Fmt.bytes(stats.swapUsed))")]) {
                            Button("View processes") {
                                state.optimization.tab = .heavy
                                state.optimization.sortByMemory = true
                                state.selection = .optimization
                            }
                            .buttonStyle(.bordered)
                        }
                        gaugeCard(title: String(localized: "Processor"), value: stats.cpu, icon: "cpu",
                                  lines: [String(localized: "Temperature: \(stats.thermalText)"), String(localized: "\(ProcessInfo.processInfo.activeProcessorCount) cores")]) {
                            Button("View processes") {
                                state.optimization.tab = .heavy
                                state.selection = .optimization
                            }.buttonStyle(.bordered)
                        }
                    }

                    HStack(spacing: 16) {
                        GlassPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Processor load", systemImage: "waveform.path.ecg").font(.headline)
                                Sparkline(values: stats.cpuHistory).frame(height: 90)
                                HStack {
                                    Label(SystemStats.speed(stats.netDown), systemImage: "arrow.down")
                                    Label(SystemStats.speed(stats.netUp), systemImage: "arrow.up")
                                    Spacer()
                                }
                                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            .padding(18)
                        }
                        batteryCard
                    }

                    securityCard
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
        .task { await refreshSecurity() }
        // When coming back from Settings (e.g. after turning on the Firewall), refreshes the state.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshSecurity() }
        }
    }

    private func gaugeCard<A: View>(title: String, value: Double, icon: String, lines: [String], @ViewBuilder action: () -> A) -> some View {
        let actionView = action()
        return GlassPanel {
            VStack(spacing: 12) {
                Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    RingGauge(value: value, lineWidth: 10, color: value > 0.85 ? Theme.amber : Theme.accent)
                    Text(Fmt.percent(value)).font(Theme.display(26)).monospacedDigit()
                }
                .frame(width: 120, height: 120)
                VStack(spacing: 2) {
                    ForEach(lines, id: \.self) { Text($0).font(.callout).foregroundStyle(.secondary) }
                }
                actionView
            }
            .padding(18)
            .frame(maxWidth: .infinity)
        }
    }

    private var batteryCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                Label("Battery", systemImage: batteryIcon).font(.headline)
                if let b = stats.battery {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(b.percent)%").font(Theme.display(34)).monospacedDigit()
                        Text(batteryState(b))
                            .foregroundStyle(.secondary)
                    }
                    if let h = b.health { row(String(localized: "Health"), Fmt.percent(h)) }
                    if let c = b.cycleCount { row(String(localized: "Cycles"), "\(c)") }
                    if let cond = b.condition { row(String(localized: "Condition"), cond == "Good" ? String(localized: "Good") : cond) }
                } else {
                    Text("No battery").foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 320)
    }

    private func batteryState(_ b: BatteryInfo) -> String {
        if b.charging { return String(localized: "charging") }
        if b.pluggedIn { return String(localized: "plugged in") }
        if let m = b.minutesRemaining { return String(localized: "\(m / 60) h \(m % 60) min remaining") }
        return String(localized: "on battery")
    }

    private var batteryIcon: String {
        guard let b = stats.battery else { return "powerplug" }
        if b.charging { return "battery.100.bolt" }
        return b.percent > 75 ? "battery.100" : b.percent > 40 ? "battery.50" : "battery.25"
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).monospacedDigit() }
    }

    private func refreshSecurity() async {
        checkingSecurity = true
        security = await SystemProtection.status()
        checkingSecurity = false
    }

    private var securityCard: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("macOS protections", systemImage: "lock.shield").font(.headline)
                    if let s = security {
                        Text(s.disabledCount == 0 ? "All on" : "\(s.activeCount) of \(s.items.count) on")
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background((s.disabledCount == 0 ? Theme.leaf : Theme.amber).opacity(0.25), in: Capsule())
                    }
                    Spacer()
                    Button {
                        Task { await refreshSecurity() }
                    } label: {
                        if checkingSecurity { ProgressView().controlSize(.small) } else { Label("Refresh", systemImage: "arrow.clockwise") }
                    }
                    .buttonStyle(.bordered)
                    .disabled(checkingSecurity)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach((security ?? SecurityStatus()).items) { securityItem($0) }
                }
                HStack(spacing: 6) {
                    if let xp = security?.xprotectVersion { Text("XProtect \(xp)") }
                    if let date = security?.checked { Text("· checked \(Fmt.relative(date))") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(18)
        }
    }

    private func securityItem(_ item: SecurityStatus.Item) -> some View {
        let on = item.enabled
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: on == nil ? "questionmark.circle" : (on! ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"))
                    .foregroundStyle(on == nil ? Color.secondary : (on! ? Theme.leaf : Theme.amber))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).font(.callout.bold())
                    Text(on == nil ? "Checking…" : (on! ? "On" : "Off")).font(.caption)
                        .foregroundStyle(on == false ? Theme.amber : Color.secondary)
                }
            }
            Text(item.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if on == false {
                if let url = item.settingsURL {
                    Button("Turn on in Settings…") { SystemProtection.openSettings(url) }
                        .buttonStyle(.bordered).controlSize(.small)
                } else if let how = item.howToEnable {
                    Text(how).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(10)
        .background(Theme.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
