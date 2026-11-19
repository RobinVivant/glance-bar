import GlanceCore
import SwiftUI

/// Shown in place of the readings: which meters the menu bar holds, in what order, and how often
/// they refresh.
struct SettingsView: View {
    @Environment(PanelModel.self) private var model
    @State private var openAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 10) {
            Card {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Menu bar").sectionTitle()
                        Spacer()
                        Text("top of the list is leftmost").font(.system(size: 10)).foregroundStyle(.tertiary)
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
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Open at login").font(.system(size: 12))
                        Spacer()
                        Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: { value in
                            guard !model.monitor.demo else { return }
                            loginError = LoginItem.set(value)
                            openAtLogin = LoginItem.isEnabled
                        }))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                    if let loginError {
                        Text(loginError).font(.system(size: 10)).foregroundStyle(Palette.amber)
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
    }

    private func row(_ meter: Meter) -> some View {
        let order = model.settings.order
        return HStack(spacing: 6) {
            Text(meter.title).font(.system(size: 12))
                .foregroundStyle(model.settings.isVisible(meter) ? .primary : .secondary)
            Spacer()
            Button {
                model.update { $0.move(meter, by: -1) }
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(order.first == meter)
            .help("Move left in the menu bar")
            Button {
                model.update { $0.move(meter, by: 1) }
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(order.last == meter)
            .help("Move right in the menu bar")
            Toggle(meter.title, isOn: Binding(get: { model.settings.isVisible(meter) },
                                              set: { value in model.update { $0.setVisible(meter, value) } }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .padding(.leading, 4)
        }
        .buttonStyle(.borderless)
        .hoverBackdrop(outset: 3, corner: 6)
    }
}
