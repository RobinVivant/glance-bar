import GlanceCore
import Observation

/// What the panel shows. It exists only while the panel is open and is
/// refreshed by the monitor's tick.
@MainActor
@Observable
final class PanelModel {
    @ObservationIgnored let monitor: Monitor
    let machine: Machine
    var snapshot: Snapshot
    var detail: Detail
    var cpuHistory: [Float]
    var upHistory: [Float]
    var downHistory: [Float]
    var settings: BarSettings
    var showingSettings = false

    init(monitor: Monitor) {
        self.monitor = monitor
        machine = monitor.demo ? DemoData.machine : Machine.current
        snapshot = monitor.snapshot
        detail = monitor.detail
        cpuHistory = monitor.cpuHistory.values
        upHistory = monitor.upHistory.values
        downHistory = monitor.downHistory.values
        settings = monitor.settings
    }

    func refresh() {
        snapshot = monitor.snapshot
        detail = monitor.detail
        cpuHistory = monitor.cpuHistory.values
        upHistory = monitor.upHistory.values
        downHistory = monitor.downHistory.values
        settings = monitor.settings
    }

    func update(_ change: (inout BarSettings) -> Void) {
        monitor.update(change)
        settings = monitor.settings
    }
}
