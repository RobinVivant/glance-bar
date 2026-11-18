import GlanceCore
import SwiftUI

struct PanelView: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
            Group {
                if model.showingSettings {
                    SettingsView().transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    readings.transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            footer
        }
        .frame(width: 360)
        .animation(.snappy(duration: 0.25), value: model.showingSettings)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.showingSettings ? "Settings" : model.machine.chip)
                    .font(.system(size: 13, weight: .semibold))
                Text(model.showingSettings ? "Glance Bar \(Self.version)" : subtitle).caption()
            }
            Spacer(minLength: 0)
            Button {
                Actions.openActivityMonitor()
            } label: {
                Image(systemName: "chart.bar.xaxis")
            }
            .buttonStyle(.borderless)
            .help("Open Activity Monitor")
            Button {
                model.showingSettings.toggle()
            } label: {
                Image(systemName: model.showingSettings ? "xmark" : "gearshape")
            }
            .buttonStyle(.borderless)
            .help(model.showingSettings ? "Back to the readings" : "Settings")
        }
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private var subtitle: String {
        var parts = ["\(model.machine.cores) cores", Format.memory(model.machine.memory)]
        if model.detail.uptime > 0 { parts.append("up \(Format.duration(model.detail.uptime))") }
        return parts.joined(separator: " · ")
    }

    private var readings: some View {
        VStack(spacing: 10) {
            tiles
            cpuCard
            if let memory = model.snapshot.memory { memoryCard(memory) }
            networkCard
            HStack(alignment: .top, spacing: 8) {
                if let disk = model.snapshot.disk { diskCard(disk) }
                if let battery = model.snapshot.battery { batteryCard(battery) }
            }
            temperatureCard
        }
    }

    // MARK: Tiles

    private var tiles: some View {
        let snapshot = model.snapshot
        return HStack(spacing: 8) {
            StatTile(value: snapshot.cpu.map { Format.percent($0.total) } ?? "–", label: "CPU",
                     color: Palette.level(snapshot.cpu.map { Levels.load($0.total) } ?? .normal, normal: .primary),
                     detail: model.detail.loadAverage.map { String(format: "load %.2f", $0) } ?? " ")
            StatTile(value: snapshot.gpu.map(Format.percent) ?? "–", label: "GPU",
                     color: Palette.level(snapshot.gpu.map(Levels.load) ?? .normal, normal: .primary),
                     detail: model.detail.gpuTemperature.map { Format.degrees($0) } ?? " ")
            StatTile(value: snapshot.memory.map { Format.percent($0.usedFraction) } ?? "–", label: "memory",
                     color: Palette.level(snapshot.memory?.pressure ?? .normal, normal: .primary),
                     detail: snapshot.memory.map { "\(Format.memory($0.used)) used" } ?? " ")
        }
    }

    // MARK: Cards

    private var cpuCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CPU").sectionTitle()
                    Spacer()
                    if let cpu = model.snapshot.cpu {
                        Text("user \(Format.percent(cpu.user)) · system \(Format.percent(cpu.system))").caption()
                    }
                }
                HistoryChart(values: model.cpuHistory, slots: Monitor.historyLength, color: Palette.cpu)
                    .frame(height: 40)
                if !model.detail.cores.isEmpty {
                    CoreBars(cores: model.detail.cores, efficiency: model.machine.efficiencyCores)
                }
            }
        }
    }

    private func memoryCard(_ memory: MemoryReading) -> some View {
        let total = Double(max(1, memory.total))
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Memory").sectionTitle()
                    Pill(text: "pressure \(Format.percent(memory.pressureFraction))",
                         color: Palette.level(memory.pressure, normal: Palette.ok))
                    Spacer()
                    Text("\(Format.memory(memory.used)) of \(Format.memory(memory.total))").caption()
                }
                CapsuleBar(parts: [(Double(memory.app) / total, Palette.memory),
                                   (Double(memory.wired) / total, Palette.wired),
                                   (Double(memory.compressed) / total, Palette.compressed)])
                HStack(spacing: 10) {
                    legend("App", Format.memory(memory.app), Palette.memory)
                    legend("Wired", Format.memory(memory.wired), Palette.wired)
                    legend("Compressed", Format.memory(memory.compressed), Palette.compressed)
                    Spacer(minLength: 0)
                }
                Text("Cached files \(Format.memory(memory.cached))"
                    + (model.detail.swapUsed.map { " · swap \(Format.memory($0))" } ?? ""))
                    .font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
            }
        }
    }

    private func legend(_ name: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(name) \(value)").caption().lineLimit(1)
        }
    }

    private var networkCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Network").sectionTitle()
                    Spacer()
                    if let interface = model.detail.interface, let address = model.detail.address {
                        Text("\(interface) · \(address)").caption()
                    }
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        rate("arrow.down", model.snapshot.network?.down, Palette.download)
                        rate("arrow.up", model.snapshot.network?.up, Palette.upload)
                    }
                    .frame(width: 92, alignment: .leading)
                    NetworkChart(down: model.downHistory, up: model.upHistory, slots: Monitor.historyLength)
                        .frame(height: 36)
                }
                if let totals = model.detail.networkTotals {
                    Text("Since boot: \(Format.storage(totals.received)) down · \(Format.storage(totals.sent)) up")
                        .font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
                }
            }
        }
    }

    private func rate(_ symbol: String, _ value: Double?, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            Text(value.map(Format.rate) ?? "–")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func diskCard(_ disk: DiskReading) -> some View {
        let level = Levels.disk(disk.usedFraction)
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Disk").sectionTitle()
                    Spacer()
                    Text(Format.percent(disk.usedFraction)).caption()
                }
                CapsuleBar(used: disk.usedFraction, color: Palette.level(level, normal: Palette.disk))
                Text("\(Format.storage(disk.free)) free of \(Format.storage(disk.total))").caption().lineLimit(1)
            }
        }
    }

    private func batteryCard(_ battery: BatteryReading) -> some View {
        let level = Levels.battery(battery)
        return Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Battery").sectionTitle()
                    Spacer()
                    Text("\(battery.percent)%").caption()
                }
                CapsuleBar(used: Double(battery.percent) / 100, color: Palette.level(level, normal: Palette.ok))
                Text(Self.batteryState(battery, health: model.detail.batteryHealth)).caption().lineLimit(1)
            }
        }
    }

    private static func batteryState(_ battery: BatteryReading, health: BatteryHealth?) -> String {
        var parts: [String] = []
        if battery.charging {
            parts.append(battery.minutesLeft.map { "full in \(Format.duration(TimeInterval($0 * 60)))" } ?? "charging")
        } else if battery.onAC {
            parts.append("on power")
        } else {
            parts.append(battery.minutesLeft.map { "\(Format.duration(TimeInterval($0 * 60))) left" } ?? "on battery")
        }
        if let health { parts.append("\(health.cycles) cycles") }
        return parts.joined(separator: " · ")
    }

    private var temperatureCard: some View {
        let cpu = model.snapshot.temperature
        let readings: [(String, Double?)] = [("CPU", cpu?.average), ("hottest core", cpu?.hottest),
                                             ("GPU", model.detail.gpuTemperature),
                                             ("SSD", model.detail.storageTemperature),
                                             ("battery", model.detail.batteryTemperature)]
        let shown = readings.filter { $0.1 != nil }
        return Group {
            if !shown.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Temperatures").sectionTitle()
                        HStack(spacing: 0) {
                            ForEach(shown, id: \.0) { name, value in
                                VStack(spacing: 1) {
                                    Text(Format.degrees(value ?? 0))
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.level(Levels.temperature(value ?? 0),
                                                                       normal: .primary))
                                    Text(name).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(Palette.ok).frame(width: 6, height: 6)
            Text(model.monitor.demo ? "Demo readings" : "Every \(model.settings.interval) s")
            Spacer(minLength: 0)
            if let cpu = model.detail.appCPU, let memory = model.detail.appMemory {
                Text("Glance Bar uses \(String(format: "%.1f", cpu * 100))% CPU · \(Format.memory(memory))")
            }
        }
        .font(.system(size: 10.5))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
    }
}
