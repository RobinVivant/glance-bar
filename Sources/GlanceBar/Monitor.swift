import AppKit
import GlanceCore
import IOKit.ps

/// Readings only the panel shows. Nothing here is sampled while the panel is closed.
struct Detail: Equatable {
    var cores: [Double] = []
    var gpuTemperature: Double?
    var batteryTemperature: Double?
    var storageTemperature: Double?
    var swapUsed: UInt64?
    var loadAverage: Double?
    var uptime: TimeInterval = 0
    var batteryHealth: BatteryHealth?
    var interface: String?
    var address: String?
    var networkTotals: InterfaceCounters?
    /// This app's own cost: share of one core averaged since launch, and memory footprint.
    var appCPU: Double?
    var appMemory: UInt64?
}

struct Machine: Equatable {
    var chip: String
    var cores: Int
    /// Efficiency cores come first in the kernel's numbering.
    var efficiencyCores: Int
    var memory: UInt64

    static let current: Machine = {
        func integer(_ name: String) -> Int {
            var value: Int32 = 0
            var size = MemoryLayout<Int32>.size
            return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : 0
        }
        return Machine(chip: TemperatureSampler.chipName, cores: ProcessInfo.processInfo.processorCount,
                       efficiencyCores: integer("hw.nperflevels") > 1 ? integer("hw.perflevel1.logicalcpu") : 0,
                       memory: ProcessInfo.processInfo.physicalMemory)
    }()
}

/// Owns the samplers and the one timer. Every tick reads only what a visible
/// meter or the open panel needs, then reports once through `onChange`.
@MainActor
final class Monitor {
    nonisolated static let historyLength = 60
    /// Disk space and the interface list change slowly: once a minute is plenty.
    nonisolated static let slowPeriod = 60

    let demo: Bool
    private(set) var settings: BarSettings
    private(set) var snapshot = Snapshot()
    private(set) var detail = Detail()
    private(set) var cpuHistory = History(capacity: Monitor.historyLength)
    private(set) var upHistory = History(capacity: Monitor.historyLength)
    private(set) var downHistory = History(capacity: Monitor.historyLength)
    /// When each reading of the CPU history and of the network histories was taken, in seconds
    /// since launch. The panel tells from these how old the column under the pointer is. A `Float`
    /// still tells whole seconds apart after three months without a restart.
    private(set) var cpuTimes = History(capacity: Monitor.historyLength)
    private(set) var networkTimes = History(capacity: Monitor.historyLength)
    private(set) var panelOpen = false
    var onChange: (() -> Void)?

    private let defaults: UserDefaults
    private let cpu = CPUSampler()
    private let memory = MemorySampler()
    private let gpu = GPUSampler()
    private let network = NetworkSampler()
    /// Opened on first use, so a bar without the temperature meter never touches the SMC.
    private lazy var temperature = TemperatureSampler()
    private var timer: DispatchSourceTimer?
    private var ticks = 0
    private var observers: [NSObjectProtocol] = []
    private var powerSource: CFRunLoopSource?
    private let launched = ProcessInfo.processInfo.systemUptime
    private let bootTime: Date? = {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0, time.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec))
    }()

    init(demo: Bool = false, defaults: UserDefaults = .standard) {
        self.demo = demo
        self.defaults = defaults
        settings = demo ? BarSettings() : BarSettings.load(from: defaults)
        if demo {
            snapshot = DemoData.snapshot
            detail = DemoData.detail
            cpuHistory = DemoData.history(DemoData.cpuHistory)
            upHistory = DemoData.history(DemoData.upHistory)
            downHistory = DemoData.history(DemoData.downHistory)
            cpuTimes = DemoData.history(DemoData.times)
            networkTimes = cpuTimes
        }
    }

    // MARK: Lifecycle

    func start() {
        guard !demo else { return }
        sampleSlow()
        sampleRates()
        sampleLevels()
        schedule()
        let center = NSWorkspace.shared.notificationCenter
        // Nobody reads a menu bar on a dark screen: stop the timer until the display is back.
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
        })
        watchPowerSource()
    }

    private func schedule() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let seconds = settings.interval
        // The leeway lets macOS line this wake-up up with others.
        timer.schedule(deadline: .now() + .seconds(seconds), repeating: .seconds(seconds),
                       leeway: .milliseconds(seconds * 100))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.resume()
        self.timer = timer
    }

    private func pause() {
        timer?.cancel()
        timer = nil
        // The first tick after the pause starts a new interval instead of averaging over the pause.
        cpu.reset()
        network.reset()
    }

    private func resume() {
        guard timer == nil, !demo else { return }
        tick()
        schedule()
    }

    /// The system tells us when the battery changes, so the battery is never polled.
    private func watchPowerSource() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<Monitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.powerSourceChanged() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        powerSource = source
    }

    private func powerSourceChanged() {
        guard wants(.battery) else { return }
        let battery = BatterySampler.read()
        guard battery != snapshot.battery else { return }
        snapshot.battery = battery
        onChange?()
    }

    // MARK: Settings and panel

    /// Settings change only from the panel, and while it is open every meter is sampled, so a
    /// meter that was just switched on already has its reading.
    func update(_ change: (inout BarSettings) -> Void) {
        var next = settings
        change(&next)
        next = next.normalized()
        guard next != settings else { return }
        let intervalChanged = next.interval != settings.interval
        settings = next
        guard !demo else {
            onChange?()
            return
        }
        settings.save(to: defaults)
        if intervalChanged, timer != nil { schedule() }
        onChange?()
    }

    func setPanelOpen(_ open: Bool) {
        guard open != panelOpen else { return }
        panelOpen = open
        guard !demo else { return }
        if open {
            // Fill in what hidden meters left out, take the per-core baseline now and a first
            // per-core reading shortly after, so the panel does not wait a whole interval.
            sampleSlow()
            sampleLevels()
            sampleDetail()
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self] in
                guard let self, self.panelOpen else { return }
                self.detail.cores = self.cpu.sampleCores() ?? self.detail.cores
                self.onChange?()
            }
        } else {
            cpu.forgetCores()
            detail = Detail()
        }
    }

    // MARK: Sampling

    private func wants(_ meter: Meter) -> Bool { panelOpen || settings.isVisible(meter) }

    private func tick() {
        ticks += 1
        if ticks % max(1, Monitor.slowPeriod / settings.interval) == 0 { sampleSlow() }
        sampleRates()
        sampleLevels()
        if panelOpen { sampleDetail() }
        onChange?()
    }

    /// Load and traffic are measured between two ticks, so only the timer reads them: a reading
    /// taken in between would put a bar worth a few milliseconds in the history. A meter nobody
    /// looks at drops its baseline and its history, so it starts afresh when it comes back.
    private func sampleRates() {
        let now = Float(ProcessInfo.processInfo.systemUptime - launched)
        if wants(.cpu) {
            if let load = cpu.sample() {
                snapshot.cpu = load
                cpuHistory.append(Float(load.total))
                cpuTimes.append(now)
            }
        } else {
            cpu.reset()
            snapshot.cpu = nil
            cpuHistory.removeAll()
            cpuTimes.removeAll()
        }
        if wants(.network) {
            if let rates = network.sample() {
                snapshot.network = rates
                upHistory.append(Float(rates.up))
                downHistory.append(Float(rates.down))
                networkTimes.append(now)
            } else if snapshot.network == nil {
                // The first reading is only a baseline. Zero keeps the slot in the bar until the
                // second one.
                snapshot.network = NetworkRates(up: 0, down: 0)
            }
        } else {
            network.reset()
            snapshot.network = nil
            upHistory.removeAll()
            downHistory.removeAll()
            networkTimes.removeAll()
        }
    }

    /// Readings that stand on their own and can be taken at any moment.
    private func sampleLevels() {
        snapshot.gpu = wants(.gpu) ? gpu.sample() : nil
        snapshot.memory = wants(.memory) ? memory.sample() : nil
        snapshot.temperature = wants(.temperature) ? temperature.cpu() : nil
    }

    private func sampleSlow() {
        snapshot.disk = wants(.disk) ? DiskSampler.read() : nil
        snapshot.battery = wants(.battery) ? BatterySampler.read() : nil
        network.forgetInterfaces()
        if panelOpen { sampleOnOpen() }
    }

    private func sampleDetail() {
        detail.cores = cpu.sampleCores() ?? detail.cores
        detail.gpuTemperature = temperature.gpu()
        detail.batteryTemperature = snapshot.battery == nil ? nil : temperature.battery()
        detail.storageTemperature = temperature.storage()
        detail.swapUsed = MemorySampler.swapUsed()
        var load = 0.0
        detail.loadAverage = getloadavg(&load, 1) == 1 ? load : nil
        detail.uptime = bootTime.map { Date().timeIntervalSince($0) } ?? ProcessInfo.processInfo.systemUptime
        detail.networkTotals = network.totals
        var usage = rusage()
        if getrusage(RUSAGE_SELF, &usage) == 0 {
            let seconds = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
            let running = ProcessInfo.processInfo.systemUptime - launched
            detail.appCPU = running > 1 ? seconds / running : nil
        }
        detail.appMemory = Self.footprint()
    }

    /// Readings that barely change while the panel is open.
    private func sampleOnOpen() {
        detail.batteryHealth = snapshot.battery == nil ? nil : BatterySampler.health()
        let address = NetworkSampler.primaryAddress()
        detail.interface = address?.interface
        detail.address = address?.address
    }

    /// Opens the panel's readings the way a click does, then fills the histories fast, for a
    /// snapshot of live readings.
    func prime() async {
        setPanelOpen(true)
        for _ in 0..<(BarContent.graphBars + 2) {
            sampleRates()
            sampleLevels()
            sampleDetail()
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// The memory figure Activity Monitor shows for this app.
    static func footprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }
}
