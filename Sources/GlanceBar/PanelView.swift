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
            .clipped()
            footer
        }
        .frame(width: 360)
        .animation(.snappy(duration: 0.25), value: model.showingSettings)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if model.showingSettings {
                title("Settings", Self.appName)
            } else {
                Button {
                    Actions.open(.about)
                } label: {
                    title(model.machine.chip.isEmpty ? "This Mac" : model.machine.chip, subtitle)
                }
                .buttonStyle(.plain)
                .hoverBackdrop(outset: 5, corner: 7)
                .pointerStyle(.link)
                .help("Open About in System Settings")
            }
            Spacer(minLength: 0)
            if !model.showingSettings {
                Button {
                    Actions.openActivityMonitor()
                } label: {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .hoverBackdrop(outset: 0, corner: 6)
                .help("Open Activity Monitor")
            }
            Button {
                model.showingSettings.toggle()
            } label: {
                Image(systemName: model.showingSettings ? "xmark" : "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .hoverBackdrop(outset: 0, corner: 6)
            .help(model.showingSettings ? "Back to the readings" : "Settings")
        }
    }

    private func title(_ name: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).font(.system(size: 13, weight: .semibold))
            Text(detail).caption()
        }
    }

    /// "Glance Bar 1.1.1". A build run outside an app bundle (`swift run`) has no version, so the
    /// name stands alone, and a README screenshot never shows a stale one.
    static var appName: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version.map { "Glance Bar \($0)" } ?? "Glance Bar"
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
            // The battery card can be a line taller: the disk card grows to match it.
            HStack(alignment: .top, spacing: 8) {
                if let disk = model.snapshot.disk { diskCard(disk) }
                if let battery = model.snapshot.battery { batteryCard(battery) }
            }
            .fixedSize(horizontal: false, vertical: true)
            temperatureCard
        }
    }

    // MARK: Tiles

    private var tiles: some View {
        let snapshot = model.snapshot
        let unit = model.settings.temperatureUnit
        let cpuLevel = snapshot.cpu.map { Levels.load($0.total) } ?? .normal
        let gpuLevel = snapshot.gpu.map(Levels.load) ?? .normal
        let memoryLevel = snapshot.memory?.pressure ?? .normal
        return HStack(spacing: 8) {
            interactive(.cpuTile, opens: "Activity Monitor", action: Actions.openActivityMonitor,
                        help: "CPU load now. \"load\" is the load average of the last minute: how many "
                            + "processes ran or waited for a core.") {
                StatTile(value: snapshot.cpu.map { Format.percent($0.total) } ?? "–", label: "CPU",
                         color: Palette.level(cpuLevel, normal: .primary),
                         detail: model.detail.loadAverage.map { String(format: "load %.2f", $0) } ?? " ",
                         fill: snapshot.cpu?.total, accent: Palette.level(cpuLevel, normal: Palette.cpu),
                         highlighted: model.hovered == .cpuTile)
            }
            interactive(.gpuTile, opens: "Activity Monitor", action: Actions.openActivityMonitor,
                        help: "Utilization of the busiest GPU, and the GPU temperature.") {
                StatTile(value: snapshot.gpu.map(Format.percent) ?? "–", label: "GPU",
                         color: Palette.level(gpuLevel, normal: .primary),
                         detail: model.detail.gpuTemperature.map { Format.degrees($0, unit: unit) } ?? " ",
                         fill: snapshot.gpu, accent: Palette.level(gpuLevel, normal: Palette.gpu),
                         highlighted: model.hovered == .gpuTile)
            }
            interactive(.memoryTile, opens: "Activity Monitor", action: Actions.openActivityMonitor,
                        help: "Memory in use: app, wired and compressed memory as a share of the total.") {
                StatTile(value: snapshot.memory.map { Format.percent($0.usedFraction) } ?? "–", label: "Memory",
                         color: Palette.level(memoryLevel, normal: .primary),
                         detail: snapshot.memory.map { "\(Format.memory($0.used)) used" } ?? " ",
                         fill: snapshot.memory?.usedFraction,
                         accent: Palette.level(memoryLevel, normal: Palette.memory),
                         highlighted: model.hovered == .memoryTile)
            }
        }
    }

    /// A tile or card that lights up under the pointer and opens the matching system tool on a
    /// click. Controls inside it keep their own clicks.
    private func interactive(_ target: PanelTarget, opens destination: String, action: @escaping () -> Void,
                             help: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        let hint = "Click to open \(destination)."
        return content()
            .contentShape(RoundedRectangle(cornerRadius: Surface.corner, style: .continuous))
            .focusable(interactions: .activate)
            .onKeyPress(.return) { action(); return .handled }
            .onKeyPress(.space) { action(); return .handled }
            .onHover { model.hover(target, $0) }
            .onTapGesture(perform: action)
            .pointerStyle(.link)
            .help(help.map { "\($0) \(hint)" } ?? hint)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: Text("Open \(destination)"), action)
            .animation(.easeOut(duration: 0.12), value: model.hovered == target)
    }

    // MARK: Cards

    private var cpuCard: some View {
        let probed = probedIndex(of: model.cpuHistory.count) {
            if case .cpuHistory(let slot) = $0 { slot } else { nil }
        }
        let cores = model.detail.cores
        let core: Int? = if case .core(let index) = model.probe, cores.indices.contains(index) {
            index
        } else {
            nil
        }
        return interactive(.cpu, opens: "Activity Monitor", action: Actions.openActivityMonitor) {
            Card(highlighted: model.hovered == .cpu) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("CPU").sectionTitle()
                        Spacer()
                        if let probed {
                            let total = Double(model.cpuHistory[probed.index])
                            let ago = age(of: probed.index, in: model.cpuHistory, taken: model.cpuTimes)
                            if model.cpuSystemHistory.count == model.cpuHistory.count {
                                let system = min(total, Double(model.cpuSystemHistory[probed.index]))
                                let user = max(0, total - system)
                                readout("\(Format.percent(total)) · user \(Format.percent(user)) · "
                                    + "sys \(Format.percent(system))\(ago)")
                            } else {
                                readout(Format.percent(total) + ago)
                            }
                        } else if let core {
                            readout(Format.core(core, efficiency: model.machine.efficiencyCores, total: cores.count)
                                + " · \(Format.percent(cores[core]))")
                        } else if let cpu = model.snapshot.cpu {
                            HStack(spacing: 8) {
                                cpuLegendDot(Palette.cpu, "user \(Format.percent(cpu.user))")
                                cpuLegendDot(Palette.cpuSystem, "system \(Format.percent(cpu.system))")
                            }
                        }
                    }
                    HistoryChart(values: model.cpuHistory, secondary: model.cpuSystemHistory,
                                 slots: Monitor.historyLength, color: Palette.cpu,
                                 secondaryColor: Palette.cpuSystem, highlight: probed?.slot) { slot in
                        probe(slot.map(Probe.cpuHistory)) { if case .cpuHistory = $0 { true } else { false } }
                    }
                    .frame(height: 40)
                    if !cores.isEmpty || model.machine.cores > 0 {
                        CoreBars(cores: cores, efficiency: model.machine.efficiencyCores,
                                 placeholderCount: model.machine.cores, highlight: core) { index, inside in
                            model.point(at: .core(index), inside)
                        }
                    }
                }
            }
        }
    }

    private func cpuLegendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).caption()
        }
    }

    // MARK: Readouts

    /// The column a chart has under the pointer and the value it draws there, if it draws one.
    private func probedIndex(of count: Int, slot: (Probe) -> Int?) -> (slot: Int, index: Int)? {
        guard let slot = model.probe.flatMap(slot),
              let index = ChartProbe.index(slot: slot, slots: Monitor.historyLength, count: count) else { return nil }
        return (slot, index)
    }

    /// A chart reports the column under the pointer, or nil when the pointer left it.
    private func probe(_ probe: Probe?, ownedBy chart: (Probe) -> Bool) {
        if let probe {
            model.point(at: probe, true)
        } else {
            model.stopProbing(where: chart)
        }
    }

    /// " · 48s ago" for a value of a history, from the times its readings were taken. Empty if
    /// the two ever disagree on how many readings there are.
    private func age(of index: Int, in values: [Float], taken times: [Double]) -> String {
        guard times.count == values.count, let age = ChartProbe.age(index: index, times: times) else { return "" }
        return " · \(Format.ago(age))"
    }

    /// What is under the pointer, in place of a card's usual caption.
    private func readout(_ text: String) -> some View {
        Text(text).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.primary).monospacedDigit()
    }

    private func memoryCard(_ memory: MemoryReading) -> some View {
        let total = Double(max(1, memory.total))
        let parts: [MemoryPart] = [.app, .wired, .compressed]
        let probed: MemoryPart? = if case .memory(let part) = model.probe { part } else { nil }
        return interactive(.memory, opens: "Activity Monitor", action: Actions.openActivityMonitor) {
            Card(highlighted: model.hovered == .memory) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Memory").sectionTitle()
                        Pill(text: "pressure \(Format.percent(memory.pressureFraction))",
                             color: Palette.level(memory.pressure, normal: Palette.ok))
                            .help("Memory pressure: the share of memory macOS can no longer hand out freely. "
                                + "The color is the kernel's own verdict: green, then orange, then red.")
                        Spacer()
                        Text("\(Format.memory(memory.used)) of \(Format.memory(memory.total))").caption()
                    }
                    CapsuleBar(parts: [(Double(memory.app) / total, Palette.memory),
                                       (Double(memory.wired) / total, Palette.wired),
                                       (Double(memory.compressed) / total, Palette.compressed)],
                               highlight: probed.flatMap(parts.firstIndex)) { index, inside in
                        model.point(at: .memory(parts[index]), inside)
                    }
                    HStack(spacing: 10) {
                        legend(.app, "App", Format.memory(memory.app), Palette.memory, probed)
                        legend(.wired, "Wired", Format.memory(memory.wired), Palette.wired, probed)
                        legend(.compressed, "Compressed", Format.memory(memory.compressed), Palette.compressed, probed)
                        Spacer(minLength: 0)
                    }
                    if let probed {
                        Text(Self.explanation(of: probed, in: memory))
                            .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.8)
                    } else {
                        let cachedHelp = "Cached files are recently used data that macOS hands back to apps on "
                            + "demand."
                        let swapHelp = model.detail.swapUsed == nil ? "" : " Swap is memory moved to the startup disk."
                        Text("Cached files \(Format.memory(memory.cached))"
                            + (model.detail.swapUsed.map { " · swap \(Format.memory($0))" } ?? ""))
                            .font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
                            .help(cachedHelp + swapHelp)
                    }
                }
            }
        }
    }

    private func legend(_ part: MemoryPart, _ name: String, _ value: String, _ color: Color,
                        _ probed: MemoryPart?) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(name) \(value)").caption().lineLimit(1)
                .foregroundStyle(probed == part ? .primary : .secondary)
        }
        .opacity(probed == nil || probed == part ? 1 : Fade.others + 0.2)
        .contentShape(Rectangle().inset(by: -3))
        .onHover { model.point(at: .memory(part), $0) }
    }

    private static func explanation(of part: MemoryPart, in memory: MemoryReading) -> String {
        func share(_ bytes: UInt64) -> String { Format.percent(Double(bytes) / Double(max(1, memory.total))) }
        return switch part {
        case .app: "App memory · \(share(memory.app)) · used by apps and their processes"
        case .wired: "Wired · \(share(memory.wired)) · stays in RAM, never compressed or swapped"
        case .compressed: "Compressed · \(share(memory.compressed)) · squeezed to make room for more"
        }
    }

    private var networkCard: some View {
        // Upload and download are appended together, so one index serves both.
        let down = model.downHistory, up = model.upHistory
        let probed = probedIndex(of: min(down.count, up.count)) {
            if case .network(let slot) = $0 { slot } else { nil }
        }
        return interactive(.network, opens: "Network settings", action: { Actions.open(.network) },
                           help: "Download (above) and upload (below) each scale to their own peak.") {
            Card(highlighted: model.hovered == .network && !model.hoveringAddress) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Network").sectionTitle()
                        Spacer()
                        if let probed, down.count == up.count {
                            readout("↓ \(Format.rate(Double(down[probed.index])))  "
                                + "↑ \(Format.rate(Double(up[probed.index])))"
                                + age(of: probed.index, in: down, taken: model.networkTimes))
                        } else if let interface = model.detail.interface, let address = model.detail.address {
                            addressButton(interface, address)
                        }
                    }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            rate("arrow.down", model.snapshot.network?.down, Palette.download)
                            rate("arrow.up", model.snapshot.network?.up, Palette.upload)
                        }
                        .frame(width: 92, alignment: .leading)
                        NetworkChart(down: down, up: up, slots: Monitor.historyLength,
                                     highlight: probed?.slot) { slot in
                            probe(slot.map(Probe.network)) { if case .network = $0 { true } else { false } }
                        }
                        .frame(height: 36)
                    }
                    let hasPeak = !down.isEmpty || !up.isEmpty
                    if model.detail.networkTotals != nil || hasPeak {
                        HStack(spacing: 8) {
                            if let totals = model.detail.networkTotals {
                                let downTotal = Format.storage(totals.received)
                                let upTotal = Format.storage(totals.sent)
                                Text("Boot \(downTotal) ↓ · \(upTotal) ↑")
                                    .lineLimit(1).minimumScaleFactor(0.85)
                                    .help("Traffic over the en* interfaces since the Mac started.")
                            }
                            Spacer(minLength: 0)
                            if hasPeak {
                                let downPeak = Format.rate(Double(down.max() ?? 0))
                                let upPeak = Format.rate(Double(up.max() ?? 0))
                                Text("Peak \(downPeak) ↓ · \(upPeak) ↑")
                                    .lineLimit(1).minimumScaleFactor(0.85)
                                    .help("Highest download and upload rates shown in the chart; "
                                        + "each half scales to its own peak.")
                            }
                        }
                        .font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
                    }
                }
            }
        }
    }

    /// The interface and its address. A click copies the address.
    private func addressButton(_ interface: String, _ address: String) -> some View {
        Button {
            model.copyAddress()
        } label: {
            ZStack(alignment: .trailing) {
                HStack(spacing: 3) {
                    Text("\(interface) · \(address)").caption()
                    Image(systemName: "doc.on.doc").font(.system(size: 8.5)).foregroundStyle(.tertiary)
                }
                .opacity(model.addressCopied ? 0 : 1)
                if model.addressCopied {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                        Text("Copied").font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(Palette.ok)
                }
            }
        }
        .buttonStyle(.plain)
        .hoverBackdrop(outset: 3, corner: 4)
        .onHover { model.hoverAddress($0) }
        .pointerStyle(.link)
        .help("Copy the address")
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
        let usedBytes = disk.total - min(disk.total, disk.free)
        let detailText = disk.purgeable >= 1_000_000_000
            ? "incl. \(Format.storage(disk.purgeable)) purgeable"
            : "\(Format.storage(usedBytes)) used"
        return interactive(.disk, opens: "Storage settings", action: { Actions.open(.storage) },
                           help: "The startup volume. Free space counts what macOS can clear on demand.") {
            Card(highlighted: model.hovered == .disk) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Disk").sectionTitle()
                        Spacer()
                        Text(Format.percent(disk.usedFraction)).caption()
                    }
                    CapsuleBar(used: disk.usedFraction, color: Palette.level(level, normal: Palette.disk))
                    Text("\(Format.storage(disk.free)) free of \(Format.storage(disk.total))").caption()
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Text(detailText).font(.system(size: 10)).foregroundStyle(.tertiary).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func batteryCard(_ battery: BatteryReading) -> some View {
        let level = Levels.battery(battery)
        return interactive(.battery, opens: "Battery settings", action: { Actions.open(.battery) }) {
            Card(highlighted: model.hovered == .battery) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Battery").sectionTitle()
                        Spacer()
                        HStack(spacing: 4) {
                            if battery.charging {
                                Image(systemName: "bolt.fill").font(.system(size: 9)).foregroundStyle(Palette.ok)
                            } else if battery.onAC {
                                Image(systemName: "powerplug.fill").font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(battery.percent)%").caption()
                        }
                    }
                    CapsuleBar(used: Double(battery.percent) / 100, color: Palette.level(level, normal: Palette.ok))
                    Text(Self.batteryStateText(battery, power: model.detail.batteryPower)).caption()
                        .lineLimit(1).minimumScaleFactor(0.85)
                    if let health = model.detail.batteryHealth {
                        Self.batteryHealth(health).caption().lineLimit(1).minimumScaleFactor(0.85)
                            .help("Health is what a full charge holds as a share of the design capacity, the "
                                + "figure macOS calls Maximum Capacity. Below 80% the battery counts as worn.")
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private static func batteryStateText(_ battery: BatteryReading, power: BatteryPower?) -> String {
        let base = Format.batteryState(battery)
        guard let power else { return base }
        if battery.charging, let watts = power.watts, watts > 0 {
            return "\(base) · +\(Format.watts(watts))"
        }
        if !battery.onAC, let watts = power.watts, watts < 0 {
            return "\(base) · \(Format.watts(-watts))"
        }
        if battery.onAC, !battery.charging, let adapter = power.adapterWatts {
            return "\(base) · \(adapter)W"
        }
        return base
    }

    /// The capacity turns amber once the battery counts as worn.
    private static func batteryHealth(_ health: BatteryHealth) -> Text {
        guard let capacity = health.capacity else { return Text("\(health.cycles) cycles") }
        var figure = Text("\(capacity)%")
        if Levels.batteryHealth(capacity) != .normal { figure = figure.foregroundStyle(Palette.amber) }
        return Text("Health \(figure) · \(health.cycles) cycles")
    }

    private var temperatureCard: some View {
        let cpu = model.snapshot.temperature
        let unit = model.settings.temperatureUnit
        let probedTemp: String? = if case .temperature(let name) = model.probe { name } else { nil }
        let readings: [(name: String, value: Double?, level: (Double) -> Level)] = [
            ("CPU", cpu?.average, Levels.temperature),
            ("hottest core", cpu?.hottest, Levels.temperature),
            ("GPU", model.detail.gpuTemperature, Levels.temperature),
            ("SSD", model.detail.storageTemperature, Levels.storageTemperature),
            ("battery", model.detail.batteryTemperature, Levels.batteryTemperature),
        ]
        let shown = readings.filter { $0.value != nil }
        return Group {
            if !shown.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Temperatures").sectionTitle()
                            Spacer()
                            if let probedTemp {
                                readout(Self.temperatureSummary(for: probedTemp, unit: unit))
                            }
                        }
                        HStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element.name) { index, item in
                                if index > 0 {
                                    Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5, height: 20)
                                }
                                let value = item.value ?? 0
                                VStack(spacing: 1) {
                                    Text(Format.degrees(value, unit: unit))
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.level(item.level(value), normal: .primary))
                                    Text(item.name).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .opacity(probedTemp == nil || probedTemp == item.name ? 1 : Fade.others)
                                .contentShape(Rectangle())
                                .onHover { model.point(at: .temperature(item.name), $0) }
                                .help(Self.temperatureSummary(for: item.name, unit: unit))
                            }
                        }
                    }
                }
            }
        }
    }

    private static func temperatureSummary(for name: String, unit: TemperatureUnit) -> String {
        func threshold(_ high: Double, _ critical: Double) -> String {
            "orange \(Format.degrees(high, unit: unit)), red \(Format.degrees(critical, unit: unit))"
        }
        return switch name {
        case "CPU": "Core average · \(threshold(90, 100))"
        case "hottest core": "Warmest core · \(threshold(90, 100))"
        case "GPU": "GPU sensors · \(threshold(90, 100))"
        case "SSD": "Storage sensor · \(threshold(65, 75))"
        case "battery": "Battery sensor · \(threshold(40, 45))"
        default: ""
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 6) {
            let status = HStack(spacing: 6) {
                Circle().fill(Palette.ok).frame(width: 6, height: 6)
                Text(model.monitor.demo ? "Demo readings" : "Every \(model.settings.interval) s")
            }
            if model.showingSettings {
                status
            } else {
                Button {
                    model.showingSettings = true
                } label: {
                    status
                }
                .buttonStyle(.plain)
                .hoverBackdrop(outset: 4, corner: 5)
                .pointerStyle(.link)
                .help("Change the refresh interval in the settings")
            }
            Spacer(minLength: 0)
            if let cpu = model.detail.appCPU, let memory = model.detail.appMemory {
                Text("Glance Bar uses \(String(format: "%.1f", cpu * 100))% CPU · \(Format.memory(memory))")
                    .help("Glance Bar's share of one core, averaged since it started, and its memory footprint.")
            }
        }
        .font(.system(size: 10.5))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5) }
    }
}
