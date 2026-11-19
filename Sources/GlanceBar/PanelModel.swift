import GlanceCore
import Observation

/// A part of the panel that lights up under the pointer and acts on a click.
enum PanelTarget: Hashable {
    case cpuTile, gpuTile, memoryTile, cpu, memory, network, disk, battery
}

/// One part of the memory bar.
enum MemoryPart: Hashable {
    case app, wired, compressed
}

/// The one reading under the pointer. Its card shows it as a readout while the pointer stays.
enum Probe: Equatable {
    /// A column of the CPU history, counted from the left.
    case cpuHistory(slot: Int)
    case core(Int)
    /// A column of the network chart, counted from the left.
    case network(slot: Int)
    case memory(MemoryPart)
}

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
    /// A view that goes away under the pointer never reports that the pointer left it, so switching
    /// screens forgets what was under it.
    var showingSettings = false {
        didSet {
            hovered = nil
            probe = nil
        }
    }
    private(set) var hovered: PanelTarget?
    private(set) var probe: Probe?
    /// True for a moment after a click copied the network address.
    private(set) var addressCopied = false
    @ObservationIgnored private var copyFlash: Task<Void, Never>?

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

    // MARK: Pointer

    /// The pointer entered or left a target. Leaving one target can be reported after entering
    /// the next, so a late "left" never clears the newer target.
    func hover(_ target: PanelTarget, _ inside: Bool) {
        if inside {
            hovered = target
        } else if hovered == target {
            hovered = nil
        }
    }

    /// Same rule as `hover(_:_:)`, for the single reading under the pointer.
    func point(at probe: Probe, _ inside: Bool) {
        if inside {
            if self.probe != probe { self.probe = probe }
        } else if self.probe == probe {
            self.probe = nil
        }
    }

    /// The pointer left a chart: drops whichever of its columns was probed.
    func stopProbing(where matches: (Probe) -> Bool) {
        if let probe, matches(probe) { self.probe = nil }
    }

    func copyAddress() {
        guard let address = detail.address else { return }
        Actions.copy(address)
        addressCopied = true
        copyFlash?.cancel()
        copyFlash = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1400))
            guard !Task.isCancelled else { return }
            self?.addressCopied = false
        }
    }
}
