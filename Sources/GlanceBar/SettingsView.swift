import GlanceCore
import SwiftUI

/// Shown in place of the readings: which meters the menu bar holds, in what order, and how often
/// they refresh.
struct SettingsView: View {
    @Environment(PanelModel.self) private var model
    @State private var openAtLogin = false
    @State private var requiresApproval = false
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 10) {
            Card {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Menu bar").sectionTitle()
                        Spacer()
                        if model.settings != BarSettings() {
                            Button("Reset") {
                                model.update { $0 = BarSettings() }
                            }
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                            .hoverBackdrop(outset: 3, corner: 4)
                            .pointerStyle(.link)
                            .help("Restore default meters, order, interval and units")
                        } else {
                            Text("top of the list is leftmost").font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                    }
                    ForEach(model.settings.order) { meter in
                        row(meter)
                    }
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Refresh every").sectionTitle()
                    let interval = Binding(get: { model.settings.interval },
                                           set: { value in model.update { $0.interval = value } })
                    Picker("Refresh every", selection: interval) {
                        ForEach(BarSettings.intervals, id: \.self) { Text("\($0) s").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            Card {
                HStack {
                    Text("Temperature").sectionTitle()
                    Spacer()
                    let unit = Binding(get: { model.settings.temperatureUnit },
                                       set: { value in model.update { $0.temperatureUnit = value } })
                    Picker("Temperature unit", selection: unit) {
                        ForEach(TemperatureUnit.allCases) { Text($0.symbol).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 96)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Open at login").font(.system(size: 12))
                            .foregroundStyle(model.monitor.demo ? .secondary : .primary)
                        Spacer()
                        Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: { value in
                            guard !model.monitor.demo else { return }
                            loginError = LoginItem.set(value)
                            openAtLogin = LoginItem.isEnabled
                            requiresApproval = LoginItem.requiresApproval
                        }))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .disabled(model.monitor.demo)
                        .help(model.monitor.demo ? "Disabled in demo mode" : "Start Glance Bar when you log in")
                    }
                    if let message = loginError ?? (requiresApproval && !model.monitor.demo
                        ? "Allow Glance Bar in System Settings > General > Login Items." : nil) {
                        Text(message).font(.system(size: 10)).foregroundStyle(Palette.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            HStack(spacing: 8) {
                Button {
                    Actions.openActivityMonitor()
                } label: {
                    Label("Activity Monitor", systemImage: "chart.bar.xaxis")
                }
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit Glance Bar", systemImage: "power")
                }
            }
            .buttonStyle(ActionButtonStyle())
        }
        .onAppear {
            guard !model.monitor.demo else { return }
            openAtLogin = LoginItem.isEnabled
            requiresApproval = LoginItem.requiresApproval
        }
    }

    private func row(_ meter: Meter) -> some View {
        let order = model.settings.order
        let unavailable = meter == .battery && model.snapshot.battery == nil
        let upDisabled = order.first == meter
        let downDisabled = order.last == meter
        let active = !unavailable && model.settings.isVisible(meter)
        return HStack(spacing: 6) {
            Image(systemName: Self.icon(for: meter))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(active ? Palette.meter(meter) : Color.secondary.opacity(0.5))
                .frame(width: 14)
            Text(meter.title).font(.system(size: 12))
                .foregroundStyle(active ? .primary : .secondary)
            if unavailable {
                Text("No battery").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                model.update { $0.move(meter, by: -1) }
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .hoverBackdrop(outset: 0, corner: 5, enabled: !upDisabled)
            .disabled(upDisabled)
            .accessibilityLabel("Move \(meter.title) left")
            .help("Move left in the menu bar")
            Button {
                model.update { $0.move(meter, by: 1) }
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .hoverBackdrop(outset: 0, corner: 5, enabled: !downDisabled)
            .disabled(downDisabled)
            .accessibilityLabel("Move \(meter.title) right")
            .help("Move right in the menu bar")
            Toggle(meter.title, isOn: Binding(get: { model.settings.isVisible(meter) },
                                              set: { value in model.update { $0.setVisible(meter, value) } }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(unavailable)
                .padding(.leading, 4)
        }
        .buttonStyle(.borderless)
    }

    private static func icon(for meter: Meter) -> String {
        switch meter {
        case .cpu: "cpu"
        case .gpu: "square.grid.2x2"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        case .temperature: "thermometer.medium"
        case .battery: "battery.75percent"
        case .network: "arrow.up.arrow.down"
        }
    }
}
