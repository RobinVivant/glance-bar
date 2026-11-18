import AppKit
import GlanceCore
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let monitor: Monitor
    private var statusItem: NSStatusItem!
    private let barView = BarView()
    private var popover: NSPopover?
    private var panel: PanelModel?
    /// The width last given to the status item. Resizing it makes AppKit and the window server
    /// rebuild the item on every display, so it happens only when the content's width changes.
    private var itemWidth: CGFloat = 0

    init(demo: Bool) {
        monitor = Monitor(demo: demo)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 {
            NSApp.terminate(nil)  // one menu bar item is enough
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: 24)
        // Demo mode leaves no trace: no login item and no remembered position.
        if !monitor.demo {
            LoginItem.enableOnFirstInstalledLaunch()
            statusItem.autosaveName = "GlanceBar"
        }
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("Glance Bar system stats")
            barView.frame = button.bounds
            barView.autoresizingMask = [.width, .height]
            button.addSubview(barView)
        }

        monitor.onChange = { [weak self] in self?.update() }
        monitor.start()
        update()
    }

    /// One pass per tick: the bar redraws only if its pixels would change, and the panel is fed
    /// only while it is open.
    private func update() {
        let content = BarContent.make(snapshot: monitor.snapshot,
                                      cpuHistory: monitor.cpuHistory.suffix(BarContent.graphBars),
                                      visible: monitor.settings.visible)
        let width = BarRenderer.width(of: content)
        if width != itemWidth {
            itemWidth = width
            statusItem.length = width
        }
        barView.content = content
        panel?.refresh()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showQuickMenu()
        } else if let popover, popover.isShown {
            popover.performClose(sender)
        } else {
            showPanel(from: sender)
        }
    }

    /// The panel is built when it opens and dropped when it closes: between
    /// clicks the app holds no SwiftUI views at all.
    private func showPanel(from button: NSStatusBarButton) {
        monitor.setPanelOpen(true)
        let panel = PanelModel(monitor: monitor)
        let host = NSHostingController(rootView: PanelView().environment(panel))
        host.sizingOptions = [.preferredContentSize]
        let popover = NSPopover()
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        self.panel = panel
        self.popover = popover
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        host.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        monitor.setPanelOpen(false)
        panel = nil
        popover = nil
    }

    private func showQuickMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Activity Monitor", action: #selector(openActivityMonitor), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Glance Bar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openActivityMonitor() { Actions.openActivityMonitor() }
}

enum Actions {
    static func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor")
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Turns "Open at Login" on once, the first time an installed copy runs. The settings toggle
    /// can turn it off for good. A registration that fails is tried again at the next launch.
    static func enableOnFirstInstalledLaunch() {
        let key = "loginItemInitialized"
        let path = Bundle.main.bundleURL.path
        guard path.hasSuffix(".app"), path.contains("/Applications/"),
              !UserDefaults.standard.bool(forKey: key) else { return }
        if isEnabled || set(true) == nil { UserDefaults.standard.set(true, forKey: key) }
    }

    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
