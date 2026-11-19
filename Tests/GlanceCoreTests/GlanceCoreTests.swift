import Foundation
import IOKit.ps
import Testing
@testable import GlanceCore

@Suite struct CPUMathTests {
    @Test func loadIsTheShareOfTicksBetweenTwoSamples() throws {
        let before = CPUTicks(user: 100, system: 50, idle: 800, nice: 50)
        let after = CPUTicks(user: 130, system: 60, idle: 850, nice: 60)
        let load = try #require(CPUMath.load(from: before, to: after))
        #expect(load.user == 0.4)  // 30 user + 10 nice of 100 ticks
        #expect(load.system == 0.1)
        #expect(load.total == 0.5)
    }

    @Test func noElapsedTicksGiveNoReading() {
        let ticks = CPUTicks(user: 1, system: 2, idle: 3, nice: 4)
        #expect(CPUMath.load(from: ticks, to: ticks) == nil)
    }

    @Test func countersThatWrapStillSubtract() throws {
        let before = CPUTicks(user: .max - 9, system: 0, idle: .max - 9, nice: 0)
        let after = CPUTicks(user: 10, system: 0, idle: 10, nice: 0)
        let load = try #require(CPUMath.load(from: before, to: after))
        #expect(load.user == 0.5)
        #expect(load.system == 0)
    }

    @Test func totalNeverExceedsOne() {
        #expect(CPULoad(user: 0.8, system: 0.4).total == 1)
    }

    @Test func theLiveSamplerNeedsTwoSamples() {
        let sampler = CPUSampler()
        #expect(sampler.sample() == nil)
        Thread.sleep(forTimeInterval: 0.2)
        if let load = sampler.sample() {
            #expect((0...1).contains(load.total))
        }
        sampler.reset()
        #expect(sampler.sample() == nil)
    }
}

@Suite struct MemoryMathTests {
    @Test func pagesSplitTheWayActivityMonitorSplitsThem() {
        let reading = MemoryMath.reading(pageSize: 16_384, total: 64 << 30, internalPages: 1000, purgeablePages: 100,
                                         wiredPages: 200, compressorPages: 50, externalPages: 300, pressure: .normal,
                                         availablePercent: 89)
        #expect(reading.app == 900 * 16_384)
        #expect(reading.wired == 200 * 16_384)
        #expect(reading.compressed == 50 * 16_384)
        #expect(reading.cached == 400 * 16_384)
        #expect(reading.used == 1150 * 16_384)
        #expect(abs(reading.pressureFraction - 0.11) < 1e-9)
    }

    @Test func morePurgeableThanInternalPagesIsZeroAppMemory() {
        let reading = MemoryMath.reading(pageSize: 4096, total: 1 << 30, internalPages: 10, purgeablePages: 20,
                                         wiredPages: 0, compressorPages: 0, externalPages: 0, pressure: .normal,
                                         availablePercent: 100)
        #expect(reading.app == 0)
        #expect(reading.pressureFraction == 0)
    }

    @Test func pressureFractionStaysBetweenZeroAndOne() {
        let low = MemoryMath.reading(pageSize: 4096, total: 1, internalPages: 0, purgeablePages: 0, wiredPages: 0,
                                     compressorPages: 0, externalPages: 0, pressure: .normal, availablePercent: 140)
        let high = MemoryMath.reading(pageSize: 4096, total: 1, internalPages: 0, purgeablePages: 0, wiredPages: 0,
                                      compressorPages: 0, externalPages: 0, pressure: .critical,
                                      availablePercent: -20)
        #expect(low.pressureFraction == 0)
        #expect(high.pressureFraction == 1)
    }

    static let pressureCases: [(Int32, Level)] = [(0, .normal), (1, .normal), (2, .high), (3, .high), (4, .critical)]

    @Test(arguments: pressureCases)
    func kernelPressureLevels(kernel: Int32, expected: Level) {
        #expect(MemoryMath.pressure(kernelLevel: kernel) == expected)
    }

    @Test func usedFractionOfAnEmptyReadingIsZero() {
        let reading = MemoryReading(total: 0, app: 1, wired: 1, compressed: 1, cached: 0, pressure: .normal,
                                    pressureFraction: 0)
        #expect(reading.usedFraction == 0)
    }

    @Test func theLiveSamplerReportsThisMac() throws {
        let reading = try #require(MemorySampler().sample())
        #expect(reading.total == ProcessInfo.processInfo.physicalMemory)
        #expect(reading.used > 0 && reading.used <= reading.total)
    }
}

@Suite struct NetworkMathTests {
    @Test func ratesAreBytesPerSecondOverAllInterfaces() throws {
        let previous: [UInt16: InterfaceCounters] = [1: .init(received: 1000, sent: 500),
                                                     2: .init(received: 0, sent: 0)]
        let current: [UInt16: InterfaceCounters] = [1: .init(received: 5000, sent: 1500),
                                                    2: .init(received: 2000, sent: 0)]
        let rates = try #require(NetworkMath.rates(previous: previous, current: current, elapsed: 2))
        #expect(rates.down == 3000)
        #expect(rates.up == 500)
    }

    @Test func aNewInterfaceAddsNothingForItsFirstInterval() throws {
        let rates = try #require(NetworkMath.rates(previous: [:], current: [4: .init(received: 9_000_000, sent: 1)],
                                                   elapsed: 2))
        #expect(rates == NetworkRates(up: 0, down: 0))
    }

    @Test func countersThatWentBackAddNothing() throws {
        let rates = try #require(NetworkMath.rates(previous: [1: .init(received: 5000, sent: 5000)],
                                                   current: [1: .init(received: 100, sent: 6000)], elapsed: 1))
        #expect(rates == NetworkRates(up: 0, down: 0))
    }

    @Test func theLiveSamplerNeedsABaselineAndForgetsItOnReset() throws {
        let sampler = NetworkSampler()
        #expect(sampler.totals == nil)
        #expect(sampler.sample() == nil)
        #expect(sampler.totals != nil)
        Thread.sleep(forTimeInterval: 0.05)
        let rates = try #require(sampler.sample())
        #expect(rates.up >= 0 && rates.down >= 0)
        sampler.reset()
        #expect(sampler.totals == nil)
        #expect(sampler.sample() == nil)
    }

    @Test func noElapsedTimeGivesNoReading() {
        #expect(NetworkMath.rates(previous: [:], current: [:], elapsed: 0) == nil)
    }

    static let interfaceCases: [(String, Bool)] = [
        ("en0", true), ("en12", true), ("utun3", false), ("lo0", false), ("bridge0", false), ("awdl0", false),
    ]

    @Test(arguments: interfaceCases)
    func onlyPhysicalInterfacesCount(name: String, counted: Bool) {
        #expect(NetworkMath.counts(interface: name) == counted)
    }
}

@Suite struct FormatTests {
    static let rateCases: [(Double, String)] = [
        (0, "0 KB/s"), (-5, "0 KB/s"), (499, "0 KB/s"), (12_400, "12 KB/s"), (999_400, "999 KB/s"),
        (999_600, "1.0 MB/s"), (1_440_000, "1.4 MB/s"), (9_960_000, "10 MB/s"), (123_400_000, "123 MB/s"),
        (1_240_000_000, "1.2 GB/s"), (12_400_000_000, "12 GB/s"), (5e12, "999 GB/s"),
    ]

    @Test(arguments: rateCases)
    func rates(bytes: Double, text: String) {
        #expect(Format.rate(bytes) == text)
    }

    @Test func everyRateFitsTheMenuBarSlot() {
        var bytes = 1.0
        while bytes < 1e13 {
            #expect(Format.rate(bytes).count <= BarContent.ratesTemplate.count, "\(bytes)")
            bytes *= 1.07
        }
    }

    static let memoryCases: [(UInt64, String)] = [
        (68_719_476_736, "64 GB"), (44_237_663_437, "41.2 GB"), (536_870_912, "512 MB"), (137_438_953_472, "128 GB"),
        (1_073_500_000, "1 GB"), (1_073_741_824, "1 GB"), (1_072_000_000, "1022 MB"), (0, "0 MB"),
    ]

    @Test(arguments: memoryCases)
    func memory(bytes: UInt64, text: String) {
        #expect(Format.memory(bytes) == text)
    }

    static let storageCases: [(UInt64, String)] = [
        (412_000_000_000, "412 GB"), (1_200_000_000_000, "1.20 TB"), (41_200_000_000, "41.2 GB"),
        (8_000_000_000, "8 GB"), (250_000_000, "250 MB"), (999_600_000, "1 GB"), (999_400_000, "999 MB"),
        (999_600_000_000, "1.00 TB"),
    ]

    @Test(arguments: storageCases)
    func storage(bytes: UInt64, text: String) {
        #expect(Format.storage(bytes) == text)
    }

    @Test func percentClampsAndRounds() {
        #expect(Format.percent(0.426) == "43%")
        #expect(Format.percent(1.7) == "100%")
        #expect(Format.percent(-1) == "0%")
    }

    @Test func degreesRound() {
        #expect(Format.degrees(61.5) == "62°")
        #expect(Format.degrees(104.2) == "104°")
    }

    static let durationCases: [(TimeInterval, String)] = [
        (0, "0m"), (2520, "42m"), (11_340, "3h 09m"), (291_600, "3d 9h"), (-10, "0m"),
    ]

    @Test(arguments: durationCases)
    func durations(seconds: TimeInterval, text: String) {
        #expect(Format.duration(seconds) == text)
    }
}

@Suite struct LevelTests {
    @Test func loadTurnsAmberThenRed() {
        #expect(Levels.load(0.84) == .normal)
        #expect(Levels.load(0.85) == .high)
        #expect(Levels.load(0.95) == .critical)
    }

    @Test func temperatureTurnsAmberThenRed() {
        #expect(Levels.temperature(89.9) == .normal)
        #expect(Levels.temperature(90) == .high)
        #expect(Levels.temperature(100) == .critical)
    }

    @Test func diskTurnsAmberThenRed() {
        #expect(Levels.disk(0.89) == .normal)
        #expect(Levels.disk(0.9) == .high)
        #expect(Levels.disk(0.95) == .critical)
    }

    @Test func aLowBatteryOnlyWarnsOffThePowerAdapter() {
        #expect(Levels.battery(BatteryReading(percent: 21, charging: false, onAC: false)) == .normal)
        #expect(Levels.battery(BatteryReading(percent: 20, charging: false, onAC: false)) == .high)
        #expect(Levels.battery(BatteryReading(percent: 10, charging: false, onAC: false)) == .critical)
        #expect(Levels.battery(BatteryReading(percent: 5, charging: true, onAC: true)) == .normal)
    }

    @Test func levelsOrderBySeverity() {
        #expect(Level.normal < .high)
        #expect(Level.high < .critical)
    }
}

@Suite struct HistoryTests {
    @Test func keepsTheNewestValuesOldestFirst() {
        var history = History(capacity: 3)
        #expect(history.last == nil)
        #expect(history.values.isEmpty)
        for value in 1...5 { history.append(Float(value)) }
        #expect(history.count == 3)
        #expect(history.values == [3, 4, 5])
        #expect(history.last == 5)
    }

    @Test func suffixTakesTheNewestAndToleratesAnyCount() {
        var history = History(capacity: 4)
        for value in 1...6 { history.append(Float(value)) }
        #expect(history.suffix(2) == [5, 6])
        #expect(history.suffix(99) == [3, 4, 5, 6])
        #expect(history.suffix(0).isEmpty)
        #expect(history.suffix(-1).isEmpty)
    }

    @Test func aPartlyFilledHistoryReturnsWhatItHas() {
        var history = History(capacity: 10)
        history.append(7)
        history.append(8)
        #expect(history.suffix(5) == [7, 8])
        #expect(history.last == 8)
    }

    @Test func removingAllStartsOver() {
        var history = History(capacity: 3)
        for value in 1...5 { history.append(Float(value)) }
        history.removeAll()
        #expect(history.count == 0)
        #expect(history.last == nil)
        history.append(9)
        history.append(10)
        #expect(history.values == [9, 10])
    }

    @Test func aZeroCapacityStillHoldsOneValue() {
        var history = History(capacity: 0)
        history.append(1)
        history.append(2)
        #expect(history.values == [2])
    }
}

@Suite struct SettingsTests {
    @Test func defaultsShowEveryMeterEveryTwoSeconds() {
        let settings = BarSettings()
        #expect(settings.visible == Meter.allCases)
        #expect(settings.interval == 2)
    }

    @Test func hidingAMeterKeepsItsPlace() {
        var settings = BarSettings()
        settings.setVisible(.gpu, false)
        #expect(!settings.isVisible(.gpu))
        #expect(settings.visible == [.cpu, .memory, .disk, .temperature, .battery, .network])
        settings.setVisible(.gpu, true)
        #expect(settings.visible == Meter.allCases)
    }

    @Test func movingSwapsNeighboursAndStopsAtTheEnds() {
        var settings = BarSettings()
        settings.move(.gpu, by: -1)
        #expect(settings.order.prefix(2) == [.gpu, .cpu])
        settings.move(.gpu, by: -1)
        #expect(settings.order.first == .gpu)
        settings.move(.network, by: 1)
        #expect(settings.order.last == .network)
    }

    @Test func roundTripsThroughJSON() throws {
        var settings = BarSettings()
        settings.setVisible(.disk, false)
        settings.move(.network, by: -1)
        settings.interval = 5
        let decoded = try JSONDecoder().decode(BarSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    @Test func settingsFromAnotherVersionStillLoad() throws {
        let json = #"{"order":["network","fan","cpu","cpu"],"hidden":["fan","gpu"],"interval":7}"#
        let settings = try JSONDecoder().decode(BarSettings.self, from: Data(json.utf8))
        #expect(settings.order == [.network, .cpu, .gpu, .memory, .disk, .temperature, .battery])
        #expect(settings.hidden == [.gpu])
        #expect(settings.interval == 2)
    }

    @Test func anEmptyObjectLoadsTheDefaults() throws {
        let settings = try JSONDecoder().decode(BarSettings.self, from: Data("{}".utf8))
        #expect(settings == BarSettings())
    }

    @Test func savesToAndLoadsFromUserDefaults() throws {
        let suite = "glance-bar-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(BarSettings.load(from: defaults) == BarSettings())
        var settings = BarSettings()
        settings.interval = 3
        settings.setVisible(.battery, false)
        settings.save(to: defaults)
        #expect(BarSettings.load(from: defaults) == settings)
        defaults.set(Data("not json".utf8), forKey: BarSettings.defaultsKey)
        #expect(BarSettings.load(from: defaults) == BarSettings())
    }
}

@Suite struct BarContentTests {
    private var snapshot: Snapshot {
        var snapshot = Snapshot()
        snapshot.cpu = CPULoad(user: 0.2, system: 0.1)
        snapshot.gpu = 0.5
        snapshot.memory = MemoryReading(total: 64 << 30, app: 30 << 30, wired: 4 << 30, compressed: 2 << 30,
                                        cached: 10 << 30, pressure: .high, pressureFraction: 0.25)
        snapshot.temperature = CPUTemperature(average: 61.6, hottest: 70)
        snapshot.battery = BatteryReading(percent: 100, charging: false, onAC: true)
        snapshot.network = NetworkRates(up: 12_000, down: 1_400_000)
        snapshot.disk = DiskReading(total: 1000, free: 80)
        return snapshot
    }

    @Test func stepsCoverTheHeightAndNeverHideASmallValue() {
        #expect(BarContent.step(0) == 0)
        #expect(BarContent.step(-1) == 0)
        #expect(BarContent.step(0.001) == 1)
        #expect(BarContent.step(0.5) == 11)
        #expect(BarContent.step(1) == 22)
        #expect(BarContent.step(3) == 22)
    }

    @Test func itemsFollowTheVisibleOrder() {
        let content = BarContent.make(snapshot: snapshot, cpuHistory: [0.5], visible: [.network, .temperature, .gpu])
        #expect(content.items == [
            .rates(up: "12 KB/s", down: "1.4 MB/s"),
            .text("62°", template: "88°", level: .normal),
            .gauge(label: "GPU", fill: 11, level: .normal),
        ])
    }

    @Test func theGraphPadsOnTheLeftAndKeepsIdleBarsVisible() throws {
        let content = BarContent.make(snapshot: snapshot, cpuHistory: [0, 0.5, 0.9, 1], visible: [.cpu])
        guard case .graph(let label, let bars, let levels) = try #require(content.items.first) else {
            Issue.record("expected a graph")
            return
        }
        #expect(label == "CPU")
        #expect(bars.count == BarContent.graphBars)
        #expect(bars.prefix(8).allSatisfy { $0 == 0 })
        #expect(Array(bars.suffix(4)) == [2, 11, 20, 22])
        #expect(Array(levels.suffix(4)) == [.normal, .normal, .high, .critical])
    }

    @Test func theGraphShowsOnlyTheNewestBars() throws {
        let history = (0..<40).map { Float($0) / 40 }
        let content = BarContent.make(snapshot: snapshot, cpuHistory: history, visible: [.cpu])
        guard case .graph(_, let bars, _) = try #require(content.items.first) else {
            Issue.record("expected a graph")
            return
        }
        #expect(bars.count == BarContent.graphBars)
        #expect(bars.last == BarContent.step(39.0 / 40))
        #expect(bars.first == BarContent.step(28.0 / 40))
    }

    @Test func theMemoryGaugeShowsPressureInTheKernelsColor() {
        let content = BarContent.make(snapshot: snapshot, cpuHistory: [], visible: [.memory])
        #expect(content.items == [.gauge(label: "MEM", fill: BarContent.step(0.25), level: .high)])
    }

    @Test func theDiskGaugeWarnsWhenNearlyFull() {
        let content = BarContent.make(snapshot: snapshot, cpuHistory: [], visible: [.disk])
        #expect(content.items == [.gauge(label: "SSD", fill: 20, level: .high)])
    }

    @Test func textSlotsWidenForThreeDigits() {
        var hot = snapshot
        hot.temperature = CPUTemperature(average: 104, hottest: 110)
        hot.battery = BatteryReading(percent: 9, charging: false, onAC: false)
        let content = BarContent.make(snapshot: hot, cpuHistory: [], visible: [.temperature, .battery])
        #expect(content.items == [
            .text("104°", template: "888°", level: .critical),
            .text("9%", template: "88%", level: .critical),
        ])
        let full = BarContent.make(snapshot: snapshot, cpuHistory: [], visible: [.battery])
        #expect(full.items == [.text("100%", template: "100%", level: .normal)])
    }

    @Test func aMeterWithoutAReadingIsLeftOut() {
        let content = BarContent.make(snapshot: Snapshot(), cpuHistory: [], visible: Meter.allCases)
        #expect(content.items.count == 1)  // the graph draws its empty frame
    }

    @Test func readingsThatDrawTheSamePixelsAreEqual() {
        var other = snapshot
        other.gpu = 0.51
        other.temperature = CPUTemperature(average: 62.4, hottest: 90)
        let a = BarContent.make(snapshot: snapshot, cpuHistory: [0.50], visible: Meter.allCases)
        let b = BarContent.make(snapshot: other, cpuHistory: [0.51], visible: Meter.allCases)
        #expect(a == b)
        other.gpu = 0.6
        #expect(a != BarContent.make(snapshot: other, cpuHistory: [0.50], visible: Meter.allCases))
    }
}

@Suite struct SMCPacketTests {
    @Test func keysAreBigEndianFourCharacterCodes() {
        #expect(SMCPacket.code("Tp01") == 0x5470_3031)
        #expect(SMCPacket.floatType == 0x666C_7420)
        #expect(SMCPacket.code("TB0Tx") == SMCPacket.code("TB0T"))
    }

    @Test func aRequestPutsEachFieldAtTheDriversOffset() {
        let packet = UnsafeMutableRawPointer.allocate(byteCount: SMCPacket.size, alignment: 8)
        defer { packet.deallocate() }
        packet.initializeMemory(as: UInt8.self, repeating: 0xFF, count: SMCPacket.size)
        SMCPacket.write(key: 0x5470_3031, command: SMCPacket.readBytes, dataSize: 4, into: packet)
        let bytes = Array(UnsafeRawBufferPointer(start: packet, count: SMCPacket.size))
        var expected = [UInt8](repeating: 0, count: 80)
        expected[0...3] = [0x31, 0x30, 0x70, 0x54]  // the key, little-endian in memory
        expected[28] = 4
        expected[42] = 5
        #expect(bytes == expected)
    }
}

@Suite struct TemperatureTests {
    static let chipCases: [(String, Int)] = [
        ("Apple M1 Max", 1), ("Apple M4", 4), ("Apple M3 Pro", 3), ("Apple M5 Ultra", 5),
    ]

    @Test(arguments: chipCases)
    func chipGenerations(brand: String, generation: Int) {
        #expect(SensorKeys.generation(of: brand) == generation)
    }

    @Test func otherProcessorsHaveNoGeneration() {
        #expect(SensorKeys.generation(of: "Intel(R) Core(TM) i9-9980HK CPU @ 2.40GHz") == nil)
        #expect(SensorKeys.generation(of: "Apple Max") == nil)
        #expect(SensorKeys.generation(of: "") == nil)
    }

    @Test func aKnownChipGetsItsOwnKeys() {
        let keys = SensorKeys.forChip("Apple M1 Max")
        #expect(keys.cpu.count == 10)
        #expect(keys.cpu.contains("Tp09"))
        #expect(keys == SensorKeys.generations[1])
    }

    @Test func anUnknownChipGetsEveryKeyOnce() {
        let keys = SensorKeys.forChip("Apple M9")
        #expect(Set(keys.cpu).count == keys.cpu.count)
        #expect(Set(keys.gpu).count == keys.gpu.count)
        for generation in SensorKeys.generations.values {
            #expect(Set(generation.cpu).isSubset(of: Set(keys.cpu)))
            #expect(Set(generation.gpu).isSubset(of: Set(keys.gpu)))
        }
    }

    @Test func everyKeyIsFourCharacters() {
        for keys in SensorKeys.generations.values {
            #expect((keys.cpu + keys.gpu).allSatisfy { $0.utf8.count == 4 })
        }
    }

    @Test func sensorsThatAreOffAreLeftOutOfTheAverage() throws {
        let summary = try #require(TemperatureMath.summarize([60, 0, 70, 250, -4, 80]))
        #expect(summary.average == 70)
        #expect(summary.hottest == 80)
        #expect(TemperatureMath.summarize([0, 0]) == nil)
        #expect(TemperatureMath.summarize([]) == nil)
    }
}

@Suite struct BatteryMathTests {
    private func source(_ changes: [String: Any] = [:]) -> [String: Any] {
        var source: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSCurrentCapacityKey: 80,
            kIOPSMaxCapacityKey: 100,
            kIOPSIsChargingKey: false,
            kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
            kIOPSTimeToEmptyKey: 245,
        ]
        source.merge(changes) { $1 }
        return source
    }

    @Test func onBatteryReportsTimeToEmpty() {
        #expect(BatteryMath.reading(from: source())
            == BatteryReading(percent: 80, charging: false, onAC: false, minutesLeft: 245))
    }

    @Test func chargingReportsTimeToFull() {
        let reading = BatteryMath.reading(from: source([
            kIOPSIsChargingKey: true, kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSTimeToFullChargeKey: 38,
        ]))
        #expect(reading == BatteryReading(percent: 80, charging: true, onAC: true, minutesLeft: 38))
    }

    @Test func anEstimateStillBeingWorkedOutIsNoEstimate() {
        #expect(BatteryMath.reading(from: source([kIOPSTimeToEmptyKey: -1]))?.minutesLeft == nil)
    }

    @Test func fullOnThePowerAdapterHasNoEstimate() {
        let reading = BatteryMath.reading(from: source([
            kIOPSCurrentCapacityKey: 100, kIOPSPowerSourceStateKey: kIOPSACPowerValue,
        ]))
        #expect(reading == BatteryReading(percent: 100, charging: false, onAC: true, minutesLeft: nil))
    }

    @Test func percentIsAShareOfTheMaximumCapacity() {
        #expect(BatteryMath.reading(from: source([kIOPSCurrentCapacityKey: 2500, kIOPSMaxCapacityKey: 5000]))?
            .percent == 50)
        #expect(BatteryMath.reading(from: source([kIOPSCurrentCapacityKey: 120]))?.percent == 100)
    }

    /// The values this M1 Max reports on macOS 27, where System Information shows 83%.
    private static let nested: [String: Any] = [
        "CycleCount": 531,
        "BatteryData": ["DesignCapacity": 6075, "NominalChargeCapacity": 5065, "AppleRawMaxCapacity": 4915],
    ]

    @Test func healthIsTheNominalShareOfTheDesignCapacity() {
        #expect(BatteryMath.health(from: Self.nested) == BatteryHealth(cycles: 531, capacity: 83))
    }

    @Test func healthReadsCapacitiesFromTheEntryItselfOnOlderSystems() {
        let flat: [String: Any] = ["CycleCount": 12, "DesignCapacity": 6000, "NominalChargeCapacity": 5400]
        #expect(BatteryMath.health(from: flat) == BatteryHealth(cycles: 12, capacity: 90))
    }

    @Test func healthFallsBackToTheRawCapacity() {
        let raw: [String: Any] = ["CycleCount": 531, "BatteryData": ["DesignCapacity": 6075, "AppleRawMaxCapacity": 4915]]
        #expect(BatteryMath.health(from: raw) == BatteryHealth(cycles: 531, capacity: 81))
    }

    @Test func aNewBatteryIsNotOverAHundredPercent() {
        let new: [String: Any] = ["CycleCount": 3, "DesignCapacity": 6075, "NominalChargeCapacity": 6249]
        #expect(BatteryMath.health(from: new) == BatteryHealth(cycles: 3, capacity: 100))
    }

    @Test func healthWithoutUsableCapacitiesKeepsTheCycles() {
        #expect(BatteryMath.health(from: ["CycleCount": 40]) == BatteryHealth(cycles: 40))
        #expect(BatteryMath.health(from: ["CycleCount": 40, "DesignCapacity": 0, "NominalChargeCapacity": 5000])
            == BatteryHealth(cycles: 40))
        #expect(BatteryMath.health(from: ["DesignCapacity": 6075, "NominalChargeCapacity": 5065]) == nil)
    }

    @Test func aWornBatteryWarnsBelowEightyPercent() {
        #expect(Levels.batteryHealth(80) == .normal)
        #expect(Levels.batteryHealth(79) == .high)
    }

    @Test func anythingButAnInternalBatteryIsIgnored() {
        #expect(BatteryMath.reading(from: source([kIOPSTypeKey: "UPS"])) == nil)
        #expect(BatteryMath.reading(from: source([kIOPSMaxCapacityKey: 0])) == nil)
        #expect(BatteryMath.reading(from: [:]) == nil)
    }
}

@Suite struct DiskTests {
    @Test func usedFractionStaysBetweenZeroAndOne() {
        #expect(DiskReading(total: 1000, free: 250).usedFraction == 0.75)
        #expect(DiskReading(total: 0, free: 0).usedFraction == 0)
        #expect(DiskReading(total: 100, free: 400).usedFraction == 0)
    }

    @Test func theLiveSamplerReadsTheStartupVolume() throws {
        let reading = try #require(DiskSampler.read())
        #expect(reading.total > 0)
        #expect(reading.free <= reading.total)
    }
}

@Suite struct ProbeTests {
    @Test func aPointMapsToItsColumn() {
        #expect(ChartProbe.slot(at: 0, width: 300, slots: 60) == 0)
        #expect(ChartProbe.slot(at: 4.9, width: 300, slots: 60) == 0)
        #expect(ChartProbe.slot(at: 5, width: 300, slots: 60) == 1)
        #expect(ChartProbe.slot(at: 299.9, width: 300, slots: 60) == 59)
    }

    @Test func aPointOutsideTheChartHasNoColumn() {
        #expect(ChartProbe.slot(at: -0.1, width: 300, slots: 60) == nil)
        #expect(ChartProbe.slot(at: 300, width: 300, slots: 60) == nil)
        #expect(ChartProbe.slot(at: 10, width: 0, slots: 60) == nil)
        #expect(ChartProbe.slot(at: 10, width: 300, slots: 0) == nil)
    }

    @Test func aFullChartMapsEveryColumnToAValue() {
        #expect(ChartProbe.index(slot: 0, slots: 60, count: 60) == 0)
        #expect(ChartProbe.index(slot: 59, slots: 60, count: 60) == 59)
    }

    @Test func aChartThatIsFillingUpKeepsItsValuesOnTheRight() {
        #expect(ChartProbe.index(slot: 59, slots: 60, count: 5) == 4)
        #expect(ChartProbe.index(slot: 55, slots: 60, count: 5) == 0)
        #expect(ChartProbe.index(slot: 54, slots: 60, count: 5) == nil)
        #expect(ChartProbe.index(slot: 59, slots: 60, count: 0) == nil)
        #expect(ChartProbe.index(slot: 60, slots: 60, count: 60) == nil)
    }

    @Test func theNewestValueIsZeroSecondsOld() {
        #expect(ChartProbe.age(index: 59, count: 60, interval: 2) == 0)
        #expect(ChartProbe.age(index: 35, count: 60, interval: 2) == 48)
        #expect(ChartProbe.age(index: 0, count: 60, interval: 5) == 295)
    }

    static let agoCases: [(Int, String)] = [(0, "now"), (-3, "now"), (48, "48 s ago"), (60, "1m 00s ago"),
                                            (96, "1m 36s ago"), (295, "4m 55s ago")]

    @Test(arguments: agoCases)
    func ages(seconds: Int, text: String) {
        #expect(Format.ago(seconds) == text)
    }

    @Test func aCoreIsNamedByItsNumberAndKind() {
        #expect(Format.core(0, efficiency: 2, total: 10) == "Core 1 · efficiency")
        #expect(Format.core(1, efficiency: 2, total: 10) == "Core 2 · efficiency")
        #expect(Format.core(2, efficiency: 2, total: 10) == "Core 3 · performance")
        #expect(Format.core(9, efficiency: 2, total: 10) == "Core 10 · performance")
    }

    @Test func aMacWithOneKindOfCoreGetsTheNumberAlone() {
        #expect(Format.core(3, efficiency: 0, total: 8) == "Core 4")
        #expect(Format.core(3, efficiency: 8, total: 8) == "Core 4")
    }

    static let batteryCases: [(BatteryReading, String)] = [
        (BatteryReading(percent: 84, charging: false, onAC: false, minutesLeft: 312), "5h 12m left"),
        (BatteryReading(percent: 84, charging: false, onAC: false), "on battery"),
        (BatteryReading(percent: 60, charging: true, onAC: true, minutesLeft: 42), "full in 42m"),
        (BatteryReading(percent: 60, charging: true, onAC: true), "charging"),
        (BatteryReading(percent: 100, charging: false, onAC: true), "on power"),
    ]

    @Test(arguments: batteryCases)
    func batteryStates(battery: BatteryReading, text: String) {
        #expect(Format.batteryState(battery) == text)
    }
}

@Suite struct BarSummaryTests {
    static var snapshot: Snapshot {
        var snapshot = Snapshot()
        snapshot.cpu = CPULoad(user: 0.27, system: 0.09)
        snapshot.gpu = 0.18
        snapshot.memory = MemoryReading(total: 64 << 30, app: 27 << 30, wired: 5 << 30, compressed: 6 << 30,
                                        cached: 14 << 30, pressure: .normal, pressureFraction: 0.24)
        snapshot.temperature = CPUTemperature(average: 58, hottest: 67)
        snapshot.battery = BatteryReading(percent: 84, charging: false, onAC: false, minutesLeft: 312)
        snapshot.network = NetworkRates(up: 184_000, down: 2_400_000)
        snapshot.disk = DiskReading(total: 994_000_000_000, free: 412_000_000_000)
        return snapshot
    }

    @Test func everyMeterGetsALineWithItsFigures() {
        #expect(BarSummary.lines(snapshot: Self.snapshot, visible: Meter.allCases) == [
            "CPU 36%: user 27%, system 9%",
            "GPU 18%",
            "Memory pressure 24%, 38 GB of 64 GB used",
            "Disk 59% used, 412 GB free",
            "CPU 58°, hottest core 67°",
            "Battery 84%, 5h 12m left",
            "Network up 184 KB/s, down 2.4 MB/s",
        ])
    }

    @Test func theLinesFollowTheOrderOfTheMenuBar() {
        #expect(BarSummary.lines(snapshot: Self.snapshot, visible: [.battery, .gpu]) == ["Battery 84%, 5h 12m left",
                                                                                         "GPU 18%"])
    }

    @Test func aMeterWithoutAReadingIsLeftOut() {
        var snapshot = Self.snapshot
        snapshot.battery = nil
        snapshot.gpu = nil
        #expect(BarSummary.lines(snapshot: snapshot, visible: [.battery, .gpu, .disk])
            == ["Disk 59% used, 412 GB free"])
        #expect(BarSummary.lines(snapshot: Snapshot(), visible: Meter.allCases).isEmpty)
    }
}
